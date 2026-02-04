# Data description

## 1. Pilot data

### EMG data

- `emg_pilot_data.csv` includes participant-level average EMG responses for each light condition and each muscle. This data is used for fitting the model used for BFDA.
- `emg_pilot_data_gavg.csv` includes the group-level average OO-EMG response trace with SD. `time_sec` is time relative to light onset.
- `emg_pilot_data_loss.csv` includes the EMG data loss for each muscle. This is defined as the proportion of all datasets for this muscle that are not included in the analysis (due to electrodes detaching, or incomplete data due to technical problems).

### Pupillary data

- `pupil_pilot_data_gavg.csv` includes the group-level average pupillary response trace with SD. Sample rate is 60 Hz.
- `pupil_pilot_data_loss.csv` includes the pupillary data loss for each participant and light condition. This is defined as the proportion of values whose associated confidence rating falls below 0.7 (0 is no confidence, 1 is total confidence).

### Subjective reporting data

- `ratings_pilot_data_gavg.csv` includes the group-level average rating for visual discomfort with SD, for each light condition.

### Light condition lookup table

- `light_conditions_lookup.json` is a lookup utility file that allows to match light condition values with melanopic EDI and illuminance values (determined through spectral measurements).

## 2. Calibration data

All calibrations were performed using the Spectraval 1511 spectrometer from JETI Technische Instrumente GmbH, Jena, Germany. The light source used is the SpectraTune Lab (Ledmotive Technologies S.L., Barcelona, Spain).

- `20240716_stlab_spectral_calibration_measurements_fullexport.xlsx` is the SpectraTune Lab light source calibration data. Each condition was sampled 15 times, i.e. for each of the 10 LEDs as well as for for white light (all LEDs at same intensity setting), at these settings: 25, 50, 100, 200, 400, 800, 1200, 1600, 2000, 2400, 2800, 3200, 3600, 4000, 4095/4095. The last, 166th measurement is the spectral measurement when the light source is off (total darkness).
- `20251028_new_settings_all.xlsx` is the spectral measurement file for the calculated primary settings corresponding to target irradiance values. The calculated values turned out to be slightly off target so they were manually corrected;
- `20251105_corrected_settings.xlsx` is the spectral measurement file for the corrected primary settings corresponding to target irradiance values.