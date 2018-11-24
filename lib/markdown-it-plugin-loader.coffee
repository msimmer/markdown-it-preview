path = require 'path'
fs = require 'fs-plus'

markdownItConfigDefaults =
  plugins: []

module.exports =
class MarkdownItPluginLoader

  constructor: ({@markdownIt})->
    @markdownItConfig = null

  getProjectPath: ->
    atom.project.getPaths()[0]

  getMarkdownItConfigPath: ->
    path.resolve "#{atom.project.getPaths()[0]}", 'markdown-it-plugin.config.js'

  getMarkdownItConfig: () ->
    return @markdownItConfig if @markdownItConfig?
    markdownItConfigPath = @getMarkdownItConfigPath()

    markdownItConfigSettings =
      if fs.isFileSync markdownItConfigPath
        require markdownItConfigPath
      else
        {}

    @markdownItConfig = Object.assign({}, markdownItConfigDefaults, markdownItConfigSettings)
    @markdownItConfig

  destructurePluginEntry: (item) ->
    entry = if Array.isArray(item) then item else [item]
    [name, opts] = entry
    args = (opts || {}).args || []
    [name, args]

  mapMarkdownItPlugins: ->
    {plugins} = @getMarkdownItConfig()
    projectPath = @getProjectPath()

    pluginList = []
    plugins.forEach (entry) =>
      [name, args] = @destructurePluginEntry(entry)
      absolutePath = path.resolve(projectPath, 'node_modules', name)

      # test that the package exists and add it to the map if it does
      try
        require.resolve absolutePath
        pluginList.push({name, absolutePath, args})
      catch error
        atom.notifications.addError "MarkdownIt Plugin Loader couldn't find package #{name}", {dismissable: true}

    pluginList

  loadMarkdownItPlugins: ->
    pluginList = @mapMarkdownItPlugins()
    return @markdownIt unless pluginList.length

    pluginList.forEach (plugin) =>
      markdownItPlugin = require plugin.absolutePath

      try
        markdownItPlugin = markdownItPlugin()
      catch error
        # TODO: handle plugins that need to be instantiated

      args = plugin.args.reduce(((acc, curr) -> acc.concat(curr)), [markdownItPlugin])
      @markdownIt.use.apply(@markdownIt, args)

    @markdownIt
