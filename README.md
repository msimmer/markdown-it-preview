# `markdown-it-preview`

This repo is a fork of the core [`markdown-preview`](https://github.com/atom/markdown-preview) package for [Atom](https://atom.io/) which replaces the [Roaster](https://github.com/gjtorikian/roaster) Markdown parser with [MarkdownIt](https://github.com/markdown-it/markdown-it).

MarkdownIt plugins can be added on a per-project basis using a config file in each project's root directory.

[**Demo project**](https://github.com/msimmer/markdown-it-preview-demo)

## Install

<ol><li>Search for and install <code>markdown-it-preview</code> in Atom's Settings view, or</li></ol>

 ```console
 $ apm install markdown-it-preview
 ```

<ol start=2><li>Disable <code>markdown-preview</code></li></ol>

## Customize

The settings from the core package still apply.  Additional options for  [`markdown-it`](https://github.com/markdown-it/markdown-it#init-with-presets-and-options) can be set there as well.

## Plugins

Start a new project and add some MarkdownIt plugins.  Note that the `markdown-it` package does not need to be installed in the new project.

```console
$ mkdir my-project && cd $_
$ npm init -y
$ npm i -S markdown-it-emoji
```

Add the `markdown-it-plugin.config.js` file to let `markdown-it-preview` know which plugins need to be loaded

```js
module.exports = {
  plugins: [
    'markdown-it-emoji'
  ],
}
```

Write some Markdown

```console
$ echo ':tada: :fireworks:' > test.md
$ atom test.md
```

Toggle Preview with <kbd>CTRL-SHIFT-M</kbd>

## License

[MIT](https://github.com/msimmer/markdown-it-preview/blob/master/LICENSE.md)
