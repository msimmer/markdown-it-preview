path = require 'path'
cheerio = require 'cheerio'
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
  quotes: '“”‘’'

  # Highlighter function. Should return escaped HTML,
  # or '' if the source string is not changed and should be escaped externaly.
  # If result starts with <pre... internal wrapper is skipped. Should be used in
  # conjunction with `langPrefix`
  highlight: -> ''

# Options loaded from Settings pane
editorMarkdownItSettings = () ->
  html:         atom.config.get 'markdown-it-preview.HTMLTagsInSource'
  xhtmlOut:     atom.config.get 'markdown-it-preview.generateXHTMLOutput'
  breaks:       atom.config.get 'markdown-it-preview.convertNewlinesToBRTags'
  langPrefix:   atom.config.get 'markdown-it-preview.languagePrefix'
  linkify:      atom.config.get 'markdown-it-preview.createLinksFromURLs'
  typographer:  atom.config.get 'markdown-it-preview.enableTypographer'
  quotes:       atom.config.get 'markdown-it-preview.quotationCharacters'

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
  markdownItSettings = Object.assign({}, defaultMarkdownItSettings, editorMarkdownItSettings())
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
  html = sanitize(html)
  html = resolveImagePaths(html, filePath)
  callback(null, html.trim())

sanitize = (html) ->
  o = cheerio.load(html)
  o('script').remove()
  attributesToRemove = [
    'onabort'
    'onblur'
    'onchange'
    'onclick'
    'ondbclick'
    'onerror'
    'onfocus'
    'onkeydown'
    'onkeypress'
    'onkeyup'
    'onload'
    'onmousedown'
    'onmousemove'
    'onmouseover'
    'onmouseout'
    'onmouseup'
    'onreset'
    'onresize'
    'onscroll'
    'onselect'
    'onsubmit'
    'onunload'
  ]
  o('*').removeAttr(attribute) for attribute in attributesToRemove
  o.html()

resolveImagePaths = (html, filePath) ->
  [rootDirectory] = atom.project.relativizePath(filePath)
  o = cheerio.load(html)
  for imgElement in o('img')
    img = o(imgElement)
    if src = img.attr('src')
      continue if src.match(/^(https?|atom):\/\//)
      continue if src.startsWith(process.resourcesPath)
      continue if src.startsWith(resourcePath)
      continue if src.startsWith(packagePath)

      if src[0] is '/'
        unless fs.isFileSync(src)
          if rootDirectory
            img.attr('src', path.join(rootDirectory, src.substring(1)))
      else
        img.attr('src', path.resolve(path.dirname(filePath), src))

  o.html()

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
    editor.setText(codeBlock.textContent)
    if grammar = atom.grammars.grammarForScopeName(scopeForFenceName(fenceName))
      editor.setGrammar(grammar)

    # Remove line decorations from code blocks.
    if editor.cursorLineDecorations?
      for cursorLineDecoration in editor.cursorLineDecorations
        cursorLineDecoration.destroy()
    else
      editor.getDecorations(class: 'cursor-line', type: 'line')[0].destroy()

    # Modify attributes once component mounted
    editorElement.setAttributeNode(document.createAttribute('gutter-hidden'))
    editorElement.removeAttribute('tabindex') # make read-only

  domFragment

tokenizeCodeBlocks = (html, defaultLanguage='text') ->
  o = cheerio.load(html)

  if fontFamily = atom.config.get('editor.fontFamily')
    o('code').css('font-family', fontFamily)

  for preElement in o("pre")
    codeBlock = o(preElement).children().first()
    fenceName = codeBlock.attr('class')?.replace(/^lang-/, '') ? defaultLanguage

    highlighter ?= new Highlights(registry: atom.grammars, scopePrefix: 'syntax--')
    highlightedHtml = highlighter.highlightSync
      fileContents: codeBlock.text()
      scopeName: scopeForFenceName(fenceName)

    highlightedBlock = o(highlightedHtml)
    # The `editor` class messes things up as `.editor` has absolutely positioned lines
    highlightedBlock.removeClass('editor').addClass("lang-#{fenceName}")

    o(preElement).replaceWith(highlightedBlock)

  o.html()
