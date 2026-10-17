# Calibration sample for nodelete-rules.yml. DATA ONLY, NEVER RUN (not executable).
# Contains 12 real delete commands the structural check must find (lines 4-15).
never_called() {
  rm -f /nonexistent/sample-target
  find /nonexistent -name x && rmdir /nonexistent/sample-dir
  /bin/rm -f /nonexistent/a
  command rm /nonexistent/b
  sudo rm /nonexistent/c
  env rm /nonexistent/d
  printf '%s\n' /nonexistent/e | xargs rm
  find /nonexistent -name '*.tmp' -delete
  find /nonexistent -name '*.tmp' -exec rm {} +
  git clean -fdx
  rsync -a --delete /nonexistent/src/ /nonexistent/dst/
  unlink /nonexistent/f
}
