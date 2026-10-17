# Calibration sample for nodelete-rules.yml. DATA ONLY, NEVER RUN (not executable).
# The same words as text only: the structural check must find 0 here.
echo 'rm -rf / is never run'   # rm in a comment
grep -c 'rm -' notes.txt
