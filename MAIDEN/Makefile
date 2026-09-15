# Local mirror of .github/workflows/ci.yml — same scripts, same order
# (lesson 15: the human path and the CI path are literally identical).
PY := .venv/bin/python

.PHONY: lint test replay ci

lint:
	.venv/bin/ruff check software scripts

test:
	.venv/bin/pytest software/tests -q

replay:
	$(PY) scripts/replay.py

ci: lint test replay
	@echo "make ci: GREEN"
