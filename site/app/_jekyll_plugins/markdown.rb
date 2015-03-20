#  Jekyll tag to include Markdown text from _includes directory preprocessing with Liquid.
#  Usage:
#    {% markdown <filename> %}
#  Dependency:
#    - redcarpet

require 'redcarpet'
require 'rouge'
require 'rouge/plugins/redcarpet'

module Jekyll

  class MarkdownTag < Liquid::Tag
    def initialize(tag_name, text, tokens)
      super
      @text = text.strip
    end

    class HTML < Redcarpet::Render::HTML
      include Rouge::Plugins::Redcarpet

      def header(title, level)
        slug = title.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
        "<h#{ level } id='#{ slug }'>#{ title }</h#{ level }>"
      end
    end

    def render(context)
      tmpl = File.read File.join Dir.pwd, "app", "_includes", @text
      site = context.registers[:site]
      tmpl = (Liquid::Template.parse tmpl).render site.site_payload
      result = HTML.new(filter_html: false, hard_wrap: true)

      options = {
        :fenced_code_blocks => true,
        :no_intra_emphasis => true,
        :autolink => true,
        :with_toc_data => true,
        :strikethrough => true,
        :lax_html_blocks => true,
        :superscript => true,
        :tables => true
      }

      markdown = Redcarpet::Markdown.new(result, options)
      markdown.render(tmpl)
    end
  end

end

Liquid::Template.register_tag('markdown', Jekyll::MarkdownTag)
