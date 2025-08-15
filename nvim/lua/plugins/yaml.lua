return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        yamlls = {}, -- Ensure yamlls is enabled if not already.
      },
    },
    init = function()
      -- Custom includeexpr for YAML files to handle $ref with #fragment.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "yaml", "yml" },
        callback = function()
          vim.opt_local.includeexpr = "v:lua.require('config.yaml.gf').yaml_include_expr(v:fname)"
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "yaml" }, -- For better YAML syntax highlighting.
    },
  },
}
