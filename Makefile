# Hammer makefile

default: test docs credo coveralls


test:
	mix test --no-start


docs:
	mix docs


credo:
	mix credo --strict


coveralls:
	mix coveralls --no-start


coveralls-travis:
	mix coveralls.travis --no-start


.PHONY: test docs credo coveralls coveralls-travis
