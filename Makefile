# Hammer makefile

test:
	mix test --no-start


docs:
	mix docs


credo:
	mix credo --strict


coveralls:
	mix coveralls


coveralls-travis:
	mix coveralls.travis


.PHONY: test docs credo coveralls coveralls-travis
