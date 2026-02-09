# emg_preprocessing.R

library(here)
library(glue)
library(tidyverse)

source(here("R", "plot_settings.R"))

metadata <- read_csv(here("data", "preprocessing_demos", "metadata.csv"))

# Variables
muscles <- c("Corrugator supercilii",
             "Orbicularis oculi",
             "Zygomaticus major",
             "Orbicularis oris")
sampling_rate_def       <- 2048     # Hz
target_fs               <- sampling_rate_def / 16
bw_filter_cutoff_def    <- 0.5      # Default cutoff for the Butterworth filter

# ---------------------------------

preprocess_emg <- function (data, 
                            pid, 
                            muscle, 
                            bw_filter_cutoff = bw_filter_cutoff_def, 
                            sampling_rate = sampling_rate_def) {
  
  # filter metadata for our example participant
  metadata_participant <- metadata %>% 
    dplyr::filter(participant_id == pid)
  
  if (muscle == "cs") {           # Corrugator supercilii
    channel_id = 1
  } else if (muscle == "ooc") {   # Orbicularis oculi
    channel_id = 2
  } else if (muscle == "zm") {    # Zygomaticus major
    channel_id = 3
  } else if (muscle == "oor") {   # Orbicularis oris
    channel_id = 4
  } else {
    stop("Muscle argument wrongly specified")
  }
  
  sprintf("Processing EMG data for participant %s, muscle %s, filter cutoff %s", pid, muscle, bw_filter_cutoff)
  # Get data from channel
  data_channel <- data[, channel_id+2][[1]]
  
  # Zero-centering
  data_channel_centered <- data_channel - mean(as.array(data_channel))
  
  # Rectify values (= take absolute values)
  data_channel_abs <- abs(data_channel_centered)
  
  # Apply filter
  # Butterworth filter
  nyquist <- sampling_rate / 2            # = 1024 Hz
  window <- bw_filter_cutoff / nyquist    # ≈ 0.00049
  filter <- signal::butter(4, window, type = "low")
  data_channel_smoothed = signal::filtfilt(filter, data_channel_abs)
  
  # Combine all data into one data frame
  data_processed <- data.frame(
    timestamp = data$timestamp,
    raw_mV = data_channel,
    centered_mV = data_channel_centered,
    abs_mV = data_channel_abs,
    smoothed_mV = data_channel_smoothed
  )
  
  # Baseline correction
  # Our baseline is the median over the last 5 minutes of the 10-min darkness adaptation
  ts_rec_start <- unique(metadata_participant$dark_period_ts) + minutes(5)
  # Select data for plateau period
  dark_period_data <- data_processed %>%
    dplyr::filter(timestamp >= ts_rec_start,
                  timestamp <= ts_rec_start + minutes(5))
  baseline <- median(dark_period_data$smoothed_mV, na.rm = TRUE)
  # Apply baseline correction
  data_processed <- data_processed %>%
    mutate(bc = smoothed_mV / baseline * 100)
  
  # parameters passed on to the function
  params <- list(
    sampling_rate = sampling_rate,
    bw_filter_cutoff = bw_filter_cutoff
  )
  # Return the processed data, and information about it
  return(list(
    data = data_processed,
    muscle = muscle,
    channel = channel_id,
    baseline = baseline,
    pid = pid,
    params = params
  ))
}

plot_emg <- function(
    data,
    which = "raw"
) {
  
  pid <- data$pid
  
  # Plotting variables
  # x_min <- min(data$data$timestamp)
  # x_max <- max(data$data$timestamp)
  y_label <- "EMG signal (mV)"
  y_lim_90 <- quantile(data$data$centered_mV, 0.9999, na.rm = TRUE) # set a common limit while discarding outliers to have a good view of the data
  show_baseline <- FALSE
  show_median <- FALSE
  
  if (which == "raw") {
    plot_df <- dplyr::transmute(data$data, timestamp = timestamp, value = raw_mV)
    title <- "*Raw data*"
    ylim <- c(-y_lim_90, y_lim_90)
  } else if (which == "zero_centered") {
    plot_df <- dplyr::transmute(data$data, timestamp = timestamp, value = centered_mV)
    title <- "**1.** Zero-centering"
    ylim <- c(-y_lim_90, y_lim_90)
  } else if (which == "rectified") {
    plot_df <- dplyr::transmute(data$data, timestamp = timestamp, value = abs_mV)
    title <- "**2.** Rectification"
    ylim <- c(0, y_lim_90)
  } else if (which == "smoothed") {
    plot_df <- dplyr::transmute(data$data, timestamp = timestamp, value = smoothed_mV)
    title <- glue("**3.** Smoothing: zero-phase 4th-order {data$params$bw_filter_cutoff} Hz low-pass Butterworth filter")
    ylim <- c(0, y_lim_90)
  } else if (which == "baseline_corrected") {
    plot_df <- dplyr::transmute(data$data, timestamp = timestamp, value = bc)
    title <- "**4.** Baseline correction: median over last 5 minutes of dark adaptation period"
    # Override some variables specifically for baseline-corrected data
    show_baseline <- TRUE
    y_label <- "% of baseline EMG signal"
    y_lim_90 <- quantile(data$data$bc, 0.9999, na.rm = TRUE)
    ylim <- c(0, y_lim_90)
  } else {
    stop("'which' argument is wrong")
  }
  
  # filter metadata for our example participant
  metadata_participant <- metadata %>% 
    dplyr::filter(participant_id == pid)
  
  med_y <- if (show_median) {
    median(dplyr::pull(data, value), na.rm = TRUE)
  } else {
    NULL
  }
  
  p <- ggplot(
    plot_df,
    aes(x = timestamp, y = value)
  ) +
    geom_line(linewidth = 0.3) +
    geom_vline(
      data = metadata_participant,
      aes(xintercept = lights_on_ts, colour = factor(melanopic_edi)),
      linewidth = 0.6,
      alpha = 0.7
    ) +
    coord_cartesian(ylim = ylim) +
    scale_colour_manual(
      name = "Melanopic EDI (lux)",
      values = colorRampPalette(c("yellow", "darkred"))(
        length(unique(metadata_participant$melanopic_edi))
      )
    ) +
    labs(title = title, x = "Time (HH:MM)", y = y_label) +
    theme_minimal() +
    plot_formatting +
    theme(plot.title = ggtext::element_markdown())
  
  # if (!is.null(x_min) || !is.null(x_max)) {
  #   p <- p + scale_x_datetime(limits = c(x_min, x_max))
  # } else {
  #   p <- p + scale_x_datetime()
  # }
  
  p <- p +
    { if (show_median) geom_hline(yintercept = med_y, colour="red", linewidth=0.6, linetype="dashed") } +
    { if (show_baseline) geom_hline(yintercept = 100, colour="red", linewidth=0.6, linetype="dashed") }
  
  p
}