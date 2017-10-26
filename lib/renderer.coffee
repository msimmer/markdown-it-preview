path = require 'path'
createDOMPurify = require 'dompurify'
fs = require 'fs-plus'
Highlights = require 'highlights'
{scopeForFenceName} = require './extension-helper'

highlighter = null
{resourcePath} = atom.getLoadSettings()
packagePath = path.dirname(__dirname)


atom.getLoadSettings()

MarkdownItPluginLoader = require './markdown-it-plugin-loader'
pluginLoader = null # Defer until used

MarkdownIt = require 'markdown-it'
markdownIt = null # Defer until used

defaultMarkdownItSettings =
  html: true                # Enable HTML tags in source
  xhtmlOut: false           # Ensure self-closing tags
  breaks: false             # Convert '\n' in paragraphs into <br>

  # CSS language prefix for fenced blocks. Setting to `lang-` will cause Atom
  # to transform `<pre />`  to embedded read-only Atom editors
  langPrefix: 'lang-'

  linkify: false            # Autoconvert URL-like text to links

  # Enable some language-neutral replacement + quotes beautification
  typographer: false

  # Double and single quotes replacement pairs, when typographer enabled,
  # and smartquotes on. Could be either a String or an Array.
  #
  # For example, you can use '«»„“' for Russian, '„“‚‘' for German,
  # and ['«\xA0', '\xA0»', '‹\xA0', '\xA0›'] for French (including nbsp).
  quotes: ['“', '”', '‘', '’']

  # Highlighter function. Should return escaped HTML,
  # or '' if the source string is not changed and should be escaped externaly.
  # If result starts with <pre... internal wrapper is skipped. Should be used in
  # conjunction with `langPrefix`
  highlight: -> ''

# Options loaded from Settings pane
getMarkdownItSettings = () ->
  # return new object to prevent mutation down the line
  __settings = atom.config.getAll('markdown-it-preview')[0].value
  settings = {}
  for key, value of __settings
    settings[key] = value

  settings

exports.toDOMFragment = (text='', filePath, grammar, callback) ->
  render text, filePath, (error, html) ->
    return callback(error) if error?

    template = document.createElement('template')
    template.innerHTML = html
    domFragment = template.content.cloneNode(true)

    # Default code blocks to be coffee in Literate CoffeeScript files
    defaultCodeLanguage = 'coffee' if grammar?.scopeName is 'source.litcoffee'
    convertCodeBlocksToAtomEditors(domFragment, defaultCodeLanguage)
    callback(null, domFragment)

exports.toHTML = (text='', filePath, grammar, callback) ->
  render text, filePath, (error, html) ->
    return callback(error) if error?
    # Default code blocks to be coffee in Literate CoffeeScript files
    defaultCodeLanguage = 'coffee' if grammar?.scopeName is 'source.litcoffee'
    html = tokenizeCodeBlocks(html, defaultCodeLanguage)
    callback(null, html)

exports.reload = () ->
  markdownItSettings = {}
  for key, value of getMarkdownItSettings()
    markdownItSettings[key] = value || defaultMarkdownItSettings[key]

  markdownIt = new MarkdownIt(markdownItSettings)

  pluginLoader = new MarkdownItPluginLoader({markdownIt})
  pluginLoader.loadMarkdownItPlugins()

  markdownIt

render = (text, filePath, callback) ->
  markdownIt ?= exports.reload()

  # Remove the <!doctype> since otherwise marked will escape it
  # https://github.com/chjj/marked/issues/354
  text = text.replace(/^\s*<!doctype(\s+.*)?>\s*/i, '')

  html = markdownIt.render(text)
  html = createDOMPurify().sanitize(html, {ALLOW_UNKNOWN_PROTOCOLS: atom.config.get('markdown-it-preview.allowUnsafeProtocols')})
  html = resolveImagePaths(html, filePath)
  callback(null, html.trim())

resolveImagePaths = (html, filePath) ->
  [rootDirectory] = atom.project.relativizePath(filePath)
  o = document.createElement('div')
  o.innerHTML = html

  for img in o.querySelectorAll('img')
    if src = img.getAttribute('src')
      continue if src.match(/^(https?|atom):\/\//)
      continue if src.startsWith(process.resourcesPath)
      continue if src.startsWith(resourcePath)
      continue if src.startsWith(packagePath)

      if src[0] is '/'
        unless fs.isFileSync(src)
          if rootDirectory
            src = path.join(rootDirectory, src.substring(1))
      else
        src = path.resolve(path.dirname(filePath), src)

      img.src = src


  o.innerHTML

convertCodeBlocksToAtomEditors = (domFragment, defaultLanguage='text') ->
  if fontFamily = atom.config.get('editor.fontFamily')
    for codeElement in domFragment.querySelectorAll('code')
      codeElement.style.fontFamily = fontFamily

  for preElement in domFragment.querySelectorAll('pre')
    codeBlock = preElement.firstElementChild ? preElement
    fenceName = codeBlock.getAttribute('class')?.replace(/^lang-/, '') ? defaultLanguage

    editorElement = document.createElement('atom-text-editor')

    preElement.parentNode.insertBefore(editorElement, preElement)
    preElement.remove()

    editor = editorElement.getModel()
    lastNewlineIndex = codeBlock.textContent.search(/\r?\n$/)
    editor.setText(codeBlock.textContent.substring(0, lastNewlineIndex)) # Do not include a trailing newline
    editorElement.setAttributeNode(document.createAttribute('gutter-hidden')) # Hide gutter
    editorElement.removeAttribute('tabindex') # Make read-only

    if grammar = atom.grammars.grammarForScopeName(scopeForFenceName(fenceName))
      editor.setGrammar(grammar)

    # Remove line decorations from code blocks.
    for cursorLineDecoration in editor.cursorLineDecorations
      cursorLineDecoration.destroy()

  domFragment

tokenizeCodeBlocks = (html, defaultLanguage='text') ->
  o = document.createElement('div')
  o.innerHTML = html

  if fontFamily = atom.config.get('editor.fontFamily')
    for codeElement in o.querySelectorAll('code')
      codeElement.style['font-family'] = fontFamily

  for preElement in o.querySelectorAll("pre")
    codeBlock = preElement.children[0]
    fenceName = codeBlock.className?.replace(/^lang-/, '') ? defaultLanguage

    highlighter ?= new Highlights(registry: atom.grammars, scopePrefix: 'syntax--')
    highlightedHtml = highlighter.highlightSync
      fileContents: codeBlock.textContent
      scopeName: scopeForFenceName(fenceName)

    highlightedBlock = document.createElement('pre')
    highlightedBlock.innerHTML = highlightedHtml
    # The `editor` class messes things up as `.editor` has absolutely positioned lines
    highlightedBlock.children[0].classList.remove('editor')
    highlightedBlock.children[0].classList.add("lang-#{fenceName}")

    preElement.outerHTML = highlightedBlock.innerHTML

  o.innerHTML
