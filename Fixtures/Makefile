output/shared_lib.wasm:
	./scripts/link-shared-lib.sh
output/main.o: main.swift
	./scripts/emit-object.sh $< $@
.PHONY: all
all: output/shared_lib.wasm output/main.o

.PHONY: clean
clean:
	rm output/shared_lib.wasm output/main.o
