#!/usr/bin/env Rscript

# Generate counterbalanced stimulus sequences using gkaguirrelab/DeBruijn,
# randomly reshuffle condition assignments,
# and save the resulting sequences as a single CSV file.
#
# This script requires the DeBruijn command-line software:
# https://github.com/gkaguirrelab/DeBruijn
#
# Install separately:
#   git clone https://github.com/gkaguirrelab/DeBruijn.git
#   cd DeBruijn
#   make
#
# Then create a project-level .Renviron file containing, for example:
#   DEBRUIJN_EXE=/Users/lbickerstaff/DeBruijn/debruijn
#
# Restart R after creating/editing .Renviron.

library(here)
library(tidyverse)

# -----------------------------
# User settings
# -----------------------------

# Number of conditions / labels
k <- 6

# Counterbalancing order
# n = 2 means every ordered pair occurs equally often in the cycle
n <- 2

# Number of randomly assigned sequences to generate
n_sequences <- 500

# Condition names used in the final output
condition_names <- seq_len(k)

# Random seed for reproducible reshuffling
random_seed <- 123

# Output file
output_csv <- here("outputs", "debruijn_sequences.csv")

# -----------------------------
# Find DeBruijn executable
# -----------------------------

debruijn_exe <- Sys.getenv("DEBRUIJN_EXE")

if (debruijn_exe == "" || !file.exists(debruijn_exe)) {
  stop(
    "Cannot find DeBruijn executable. Check DEBRUIJN_EXE in your .Renviron file.",
    call. = FALSE
  )
}

# -----------------------------
# Checks
# -----------------------------

if (length(condition_names) != k) {
  stop("condition_names must have length k.", call. = FALSE)
}

dir.create(dirname(output_csv), recursive = TRUE, showWarnings = FALSE)

# -----------------------------
# Run DeBruijn once
# -----------------------------

cmd_output <- system2(
  command = debruijn_exe,
  args = c(k, n),
  stdout = TRUE,
  stderr = TRUE
)

# For k = 6, labels should be 0, 1, 2, 3, 4, 5.
allowed_labels <- as.character(0:(k - 1))

raw_sequence <- cmd_output %>%
  paste(collapse = "\n") %>%
  str_extract_all("[0-9A-Z]") %>%
  unlist() %>%
  keep(~ .x %in% allowed_labels)

expected_length <- k^n

if (length(raw_sequence) < expected_length) {
  stop(
    "Parsed sequence is shorter than expected.\n",
    "Expected at least ", expected_length, " labels, got ", length(raw_sequence), ".\n\n",
    "Full command output was:\n",
    paste(cmd_output, collapse = "\n"),
    call. = FALSE
  )
}

raw_sequence <- raw_sequence[seq_len(expected_length)]

original_labels <- sort(unique(raw_sequence))

if (length(original_labels) != k) {
  stop(
    "Expected ", k, " unique labels, but found ",
    length(original_labels), ": ",
    paste(original_labels, collapse = ", "),
    call. = FALSE
  )
}

# -----------------------------
# Generate multiple randomised sequences
# -----------------------------

set.seed(random_seed)

all_sequences <- vector("list", n_sequences)

for (sequence_id in seq_len(n_sequences)) {
  
  # Randomly reshuffle mapping from DeBruijn labels to experimental conditions
  reshuffled_conditions <- sample(condition_names, size = k, replace = FALSE)
  
  condition_key <- tibble(
    sequence_id = sequence_id,
    debruijn_label = original_labels,
    assigned_condition = reshuffled_conditions
  )
  
  # Random circular rotation.
  # This preserves DeBruijn counterbalancing but changes where the sequence starts.
  start_position <- sample(seq_along(raw_sequence), size = 1)
  
  rotated_sequence <- c(
    raw_sequence[start_position:length(raw_sequence)],
    raw_sequence[seq_len(start_position - 1)]
  )
  
  sequence_df <- tibble(
    sequence_id = sequence_id,
    trial = seq_along(rotated_sequence),
    debruijn_label = rotated_sequence
  ) %>%
    left_join(condition_key, by = c("sequence_id", "debruijn_label"))
  
  # Check pairwise counterbalancing using circular wrapping
  transition_check <- sequence_df %>%
    mutate(
      previous_label = lag(debruijn_label, default = last(debruijn_label)),
      transition = paste0(previous_label, "->", debruijn_label)
    ) %>%
    count(transition, name = "n")
  
  if (length(unique(transition_check$n)) != 1) {
    warning(
      "Transitions are not perfectly balanced for sequence ",
      sequence_id,
      "."
    )
  }
  
  all_sequences[[sequence_id]] <- sequence_df
}

sequence_df_all <- bind_rows(all_sequences)

# -----------------------------
# Save
# -----------------------------

write_csv(sequence_df_all, output_csv)

message("Successfully saved sequences")
message("Number of sequences: ", n_sequences)
message("Trials per sequence: ", expected_length)
message("Total rows: ", nrow(sequence_df_all))