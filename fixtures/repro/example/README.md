# claudecode.nvim repro workspace

This directory is copied into a temp workspace when you run `repro`.

## Quick start

From the repo root:

```sh
source fixtures/nvim-aliases.sh
repro
```

That will:

- create `/tmp/claudecode.nvim-repro` (reset on every run)
- open Neovim with the **minimal** `fixtures/repro` config
- open `a.txt` so your current window is non-empty

## Reproducing issue #155 (leftover diff split)

Goal: confirm that after accepting a diff for a file that was *not* already open, we do **not** leave behind an extra split.

1. In Neovim, note window count:

   ```vim
   :echo winnr('$')
   ```

2. Start Claude:

   ```vim
   :ClaudeCode
   ```

3. In the Claude terminal, ask Claude to make a small edit to `b.txt`.

   **Important:** Do *not* open `b.txt` in a Neovim window yourself before the diff opens.

4. When the diff opens, accept it:

   - `:w` from the proposed buffer **or**
   - `<leader>aa`

5. Wait for Claude to close the diff (the plugin cleans up when Claude calls `close_tab`).

6. Confirm window count returned to what it was in step 1:

   ```vim
   :echo winnr('$')
   ```

You should not see an orphaned split after accept.

## Notes

- This fixture uses the **native** terminal provider to avoid depending on external plugins.
- To tweak the config, edit `fixtures/repro/init.lua` (or run `vve repro`).
