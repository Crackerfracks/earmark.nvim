NVIM ?= nvim
MINI := $(firstword $(wildcard $(HOME)/.local/share/nvim/lazy/mini.nvim) deps/mini.nvim)

test: $(MINI)
	MINI_PATH=$(MINI) $(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

test-file: $(MINI)
	MINI_PATH=$(MINI) $(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# a small annotated project in /tmp/earmark-demo, and the command that opens it
demo:
	@$(NVIM) --headless --clean -l scripts/demo.lua

lint:
	@if command -v stylua >/dev/null 2>&1; then stylua --check lua tests scripts; else echo "stylua not installed"; fi

# optional: lets the flash jump and which-key tests run instead of being skipped
deps: deps/mini.nvim deps/flash.nvim deps/which-key.nvim

deps/which-key.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/folke/which-key.nvim $@

deps/flash.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/folke/flash.nvim $@

deps/mini.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

.PHONY: test test-file demo lint deps
