-- `make demo`: writes a small annotated project to $EARMARK_DEMO (default /tmp/earmark-demo)
-- and prints the command that opens it with this checkout of earmark. It is the same project
-- the clips in docs/demos are recorded in, so their "Try it yourself" steps work in it.
local repo = vim.fn.getcwd()
_G.arg = { repo, os.getenv('EARMARK_DEMO') or '/tmp/earmark-demo' }
dofile(repo .. '/docs/demos/scripts/fixture.lua')
