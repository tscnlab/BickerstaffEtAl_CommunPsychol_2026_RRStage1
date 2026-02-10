**PCI-RR Stage 1 Manuscript: Bickerstaff et al., Objective and subjective assessment of light sensitivity in physiological responses to bright light in humans (2026)**

Exploratory analyses:

1. Pupillometry data:
   
- The drifting pre-stimulus baselines and model it as a function of light level and trial number `baseline ~ trial_no + previous_light_condition` using linear models
- The impact these baselines (and other carryover effects) have on the constriction amplitude

2. IR video recordings:

- Extract Facial Action Units (FACS) data, using proprietary software (e.g. FaceReader) as well as exploring custom scripts using tools like OpenCV
- Relate the FACS data with the related facial sEMG and pupillometry data using correlation analyses

3. Clustering of data

- Principal Component Analysis (PCA) will be run on the data to identify potential clustering of physiological responses to bright light
