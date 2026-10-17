# Calibration sample for nodelete-rules.yml. DATA ONLY, NEVER RUN (not executable).
# The same words as text or harmless commands only: the structural check must find 0 here.
echo 'rm -rf / is never run'   # rm in a comment
grep -c 'rm -' notes.txt
echo find . -delete
git status
rsync -a src/ dst/
command ls
# Known false positive, so not in this file: `env FOO=1 printf '%s\n' rm` is flagged. The
# wrapper rule counts any rm word in an env/sudo/xargs/... command.
