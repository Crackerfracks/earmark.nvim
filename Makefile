NVIM ?= nvim
MINI := $(firstword $(wildcard $(HOME)/.local/share/nvim/lazy/mini.nvim) deps/mini.nvim)

test: $(MINI)
	MINI_PATH=$(MINI) $(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

test-file: $(MINI)
	MINI_PATH=$(MINI) $(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

lint:
	@if command -v stylua >/dev/null 2>&1; then stylua --check lua tests scripts; else echo "stylua not installed"; fi

deps/mini.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

.PHONY: test test-file lint
