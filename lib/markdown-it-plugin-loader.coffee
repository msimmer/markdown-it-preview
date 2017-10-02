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

  getPackageJsonPath: ->
    path.resolve "#{atom.project.getPaths()[0]}", 'package.json'

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

  getPackageJson: ->
    packageJsonPath = @getPackageJsonPath()
    return null unless fs.isFileSync packageJsonPath
    return JSON.parse fs.readFileSync packageJsonPath

  getMarkdownItPackages: ->
    packages = []
    packageJson = @getPackageJson()
    return packages unless packageJson

    {dependencies, devDependencies} = packageJson
    packages = Object.assign({}, dependencies, devDependencies)
    packages = Object.keys(dependencies).filter((_) -> /^markdown-it-/.test(_))

    packages

  destructurePluginEntry: (item) ->
    entry = if Array.isArray(item) then item else [item]
    [name, opts] = entry
    args = (opts || {}).args || []
    [name, args]

  mapMarkdownItPlugins: ->
    packages = @getMarkdownItPackages()
    {plugins} = @getMarkdownItConfig()
    projectPath = @getProjectPath()

    pluginMap = new Map()
    plugins.forEach (entry) =>
      [name, args] = @destructurePluginEntry(entry)
      absolutePath = path.resolve(projectPath, 'node_modules', name)

      pluginMap.set(name, {absolutePath, args})

    pluginMap

  loadMarkdownItPlugins: ->
    pluginMap = @mapMarkdownItPlugins()
    return @markdownIt unless pluginMap.size

    pluginMap.forEach (plugin) =>
      markdownItPlugin = require plugin.absolutePath

      try
        markdownItPlugin = markdownItPlugin()
      catch error
        # TODO: handle plugins that need to be instantiated

      args = plugin.args.reduce(((acc, curr) -> acc.concat(curr)), [markdownItPlugin])
      @markdownIt.use.apply(@markdownIt, args)

    @markdownIt
