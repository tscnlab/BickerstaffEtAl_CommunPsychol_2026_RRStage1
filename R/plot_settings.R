# plot_settings.R

library(here)
library(lubridate)

delay       <- seconds(10)
ramp_up     <- seconds(3)
plateau     <- seconds(30)
ramp_down   <- seconds(3)
refr_period <- seconds(30)

n_trials <- 36

shaded_region_yellow <- data.frame(
  xmin = as.numeric(-delay),
  xmax = as.numeric(-delay + ramp_up + plateau + ramp_down),
  ymin = -Inf,
  ymax = Inf
)

shaded_region_orange <- data.frame(
  xmin = as.numeric(-delay + ramp_up),
  xmax = as.numeric(-delay + ramp_up + plateau),
  ymin = -Inf,
  ymax = Inf
)

muscles <- c("corrugator supercilii",
             "orbicularis oculi",
             "zygomaticus major",
             "orbicularis oris")

breaks <- c(0.1, 0.3, 1, 3, 10, 30, 100, 300, 1000, 3000, 10000)
minor_breaks <- rep(1:9, 21)*(10^rep(-10:10, each=9))

plot_formatting <- theme(
  text = element_text(size = 9, family = "Arial"),
  axis.title = element_text(size = 9),
  axis.text  = element_text(size = 8),
  legend.title = element_text(size = 9),
  legend.text  = element_text(size = 8)
)

# function so running doesn't stop if the target dir doesn't exist
ggsave_safe <- function(filename, plot, ...) {
  dir <- dirname(filename)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  ggsave(filename, plot = plot, ...)
}

# function to save plot in manuscript-ready format
formatted_save <- function(name, plot, width = 7, height = 4) {
  ggsave_safe(name, 
              plot,
              width = width,
              height = height,
              units = "in")
}