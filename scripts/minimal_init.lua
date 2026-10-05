-- Used both by the test runner and by child Neovim processes in tests.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(os.getenv('MINI_PATH') or (vim.fn.stdpath('data') .. '/lazy/mini.nvim'))
vim.o.swapfile = false
vim.o.shadafile = 'NONE'
require('mini.test').setup()
