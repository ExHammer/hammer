# Hammer makefile

default: format test docs coveralls


format:
	mix format mix.exs "lib/**/*.{ex,exs}" "test/**/*.{ex,exs}"


test: format
	mix test --no-start


docs:
	mix docs


coveralls:
	mix coveralls --no-start


coveralls-travis:
	mix coveralls.travis --no-start


.PHONY: format test docs coveralls coveralls-travis
