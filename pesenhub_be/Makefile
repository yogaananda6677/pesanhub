.PHONY: setup dev build rebuild start stop down restart logs status health test check fmt migrate-up migrate-down migrate-status version run-local

setup dev build rebuild start stop down restart logs status health test check fmt migrate-up migrate-status version:
	./run.sh $@

migrate-down:
	./run.sh migrate-down

run-local:
	go run ./cmd/api
