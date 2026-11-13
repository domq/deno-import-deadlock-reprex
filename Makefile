# Regenerates the forensic evidence for the hand-written deadlock repro (macOS).
#
#   make evidence-osx   capture evidence/stack-sample.txt + evidence/debug-log.txt
#   make clean          remove the captured evidence
#
# The repro hangs by design: each capture starts `deno run -A main.js`, waits
# until the process is wedged in op_import_sync, records what is needed
# (sample(1) of all threads / --log-level=debug output), then kills it.
# If the process exits before deadlocking, the target fails loudly.

DENO       ?= deno
HANG_WAIT  ?= 8      # seconds to wait for the process to reach the deadlock
SAMPLE_SECS ?= 2     # duration passed to sample(1)

EVIDENCE := evidence
SAMPLE   := $(EVIDENCE)/stack-sample.txt
DEBUGLOG := $(EVIDENCE)/debug-log.txt
VERSIONS := $(EVIDENCE)/versions.txt

.PHONY: evidence-osx clean
.PHONY: $(SAMPLE) $(DEBUGLOG) $(VERSIONS)   # always recapture

evidence-osx: $(VERSIONS) $(DEBUGLOG) $(SAMPLE)

$(VERSIONS):
	@mkdir -p $(EVIDENCE)
	@{ $(DENO) --version; sw_vers 2>/dev/null; uname -m; } > $@

# Debug log of the hung process: shows the in-flight dynamic-import prepare
# (p2: "Preparing/Building module graph.", never "Prepared") and the sync
# require that never gets to log its own prepare (parked on the permit).
$(DEBUGLOG):
	@mkdir -p $(EVIDENCE)
	@echo "capturing $@ (process hangs by design)…"
	@$(DENO) run -A --log-level=debug main.js > $@ 2>&1 & \
	pid=$$!; \
	trap 'kill -9 $$pid 2>/dev/null' EXIT; \
	sleep $(HANG_WAIT); \
	if kill -0 $$pid 2>/dev/null; then \
	  echo "  process $$pid wedged as expected"; \
	else \
	  echo "ERROR: process exited before deadlocking; see $@" >&2; \
	  exit 1; \
	fi; \
	tail -3 $@

# All-thread sample of the hung process: main thread blocked in
# op_import_sync -> run_future_in_new_runtime -> scoped join -> __ulock_wait,
# inner runtime parked in the tokio event loop.
$(SAMPLE):
	@mkdir -p $(EVIDENCE)
	@echo "capturing $@ (process hangs by design)…"
	@$(DENO) run -A main.js > /dev/null 2>&1 & \
	pid=$$!; \
	trap 'kill -9 $$pid 2>/dev/null' EXIT; \
	sleep $(HANG_WAIT); \
	if ! kill -0 $$pid 2>/dev/null; then \
	  echo "ERROR: process exited before deadlocking" >&2; \
	  exit 1; \
	fi; \
	echo "  process $$pid wedged as expected; sampling for $(SAMPLE_SECS)s…"; \
	sample $$pid $(SAMPLE_SECS) -file $@ > /dev/null; \
	grep -m1 -q 'op_import_sync' $@ || { echo "ERROR: $@ lacks the expected op_import_sync signature" >&2; exit 1; }; \
	echo "  wrote $@"

clean:
	rm -rf $(EVIDENCE)
