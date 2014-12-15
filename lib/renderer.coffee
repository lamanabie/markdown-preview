path = require 'path'
_ = require 'underscore-plus'
cheerio = require 'cheerio'
fs = require 'fs-plus'
Highlights = require 'highlights'
{$} = require 'atom-space-pen-views'
roaster = null # Defer until used
{scopeForFenceName} = require './extension-helper'

highlighter = null
{resourcePath} = atom.getLoadSettings()
packagePath = path.dirname(__dirname)

exports.footnote = (text) ->
  createFootnote = (text) ->
    text.replace /\[\^(.+?)\]/g, (wholeMatch, m1) ->
      if (fn[m1] == undefined)
        return ''
      return '<sup><a href="#fn:'+ fn[m1]['key']+'" id="fnref:'+fn[m1]['key']+'" title="See footnote" class="footnote">'+fn[m1]['position']+'</a></sup>'

  fn = []
  count = 0
  text = text.replace /\[\^(.+?)\]:(.+?)[\r\n]+((\s+)(.+?)[\r\n]+)*/gm, (wholeMatch, m1, m2, m3, m4) ->
    paragraphs = (wholeMatch.replace /\[\^(.+?)\]:/, '').split "\n"

    fn[m1] = []
    fn[m1]['key'] = m1.toLowerCase().replace(/[^a-zA-Z0-9]+/g,'-')
    fn[m1]['text'] = []
    for property of paragraphs
      if paragraphs[property].trim().length > 0
        fn[m1]['text'].push paragraphs[property].trim()


    fn[m1]['position'] = ++count
    return ""

  text = createFootnote text

  text += """
  <div class="footnotes">
    <hr>
      <ol>"""

  for property of fn
    text += '<li id="fn:' + fn[property]['key'] + '">'
    i = 0
    while i < fn[property]['text'].length
      p = createFootnote fn[property]['text'][i]

      text += '<p style="margin: 0;padding: 0;">' + p + '</p>'
      i++
    text += ' <a href="#fnref:' + fn[property]['key'] + '" title="Return to article" class="reversenote">&larr;</a></li>'

  text += """</ol>
    </div>"""
  text

exports.toHtml = (text='', filePath, grammar, callback) ->
  roaster ?= require 'roaster'
  options =
    sanitize: false
    breaks: atom.config.get('markdown-preview.breakOnSingleNewline')

  # Remove the <!doctype> since otherwise marked will escape it
  # https://github.com/chjj/marked/issues/354
  text = text.replace(/^\s*<!doctype(\s+.*)?>\s*/i, '')
  text = exports.footnote text

  roaster text, options, (error, html) =>
    return callback(error) if error

    grammar ?= atom.grammars.selectGrammar(filePath, text)
    # Default code blocks to be coffee in Literate CoffeeScript files
    defaultCodeLanguage = 'coffee' if grammar.scopeName is 'source.litcoffee'

    html = sanitize(html)
    html = resolveImagePaths(html, filePath)
    html = tokenizeCodeBlocks(html, defaultCodeLanguage)
    callback(null, html.html().trim())

exports.toText = (text, filePath, grammar, callback) ->
  exports.toHtml text, filePath, grammar, (error, html) ->
    if error
      callback(error)
    else
      string = $(document.createElement('div')).append(html)[0].innerHTML
      callback(error, string)

sanitize = (html) ->
  o = cheerio.load("<div>#{html}</div>")
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
  html = $(html)
  for imgElement in html.find('img')
    img = $(imgElement)
    if src = img.attr('src')
      continue if src.match(/^(https?|atom):\/\//)
      continue if src.startsWith(process.resourcesPath)
      continue if src.startsWith(resourcePath)
      continue if src.startsWith(packagePath)

      if src[0] is '/'
        unless fs.isFileSync(src)
          img.attr('src', atom.project.resolve(src.substring(1)))
      else
        img.attr('src', path.resolve(path.dirname(filePath), src))

  html

tokenizeCodeBlocks = (html, defaultLanguage='text') ->
  html = $(html)

  if fontFamily = atom.config.get('editor.fontFamily')
    $(html).find('code').css('font-family', fontFamily)

  for preElement in $.merge(html.filter("pre"), html.find("pre"))
    codeBlock = $(preElement.firstChild)
    fenceName = codeBlock.attr('class')?.replace(/^lang-/, '') ? defaultLanguage

    highlighter ?= new Highlights(registry: atom.grammars)
    highlightedHtml = highlighter.highlightSync
      fileContents: codeBlock.text()
      scopeName: scopeForFenceName(fenceName)

    highlightedBlock = $(highlightedHtml)
    # The `editor` class messes things up as `.editor` has absolutely positioned lines
    highlightedBlock.removeClass('editor').addClass("lang-#{fenceName}")
    highlightedBlock.insertAfter(preElement)
    preElement.remove()

  html
