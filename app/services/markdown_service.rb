class MarkdownService
  include Singleton

  class MarkdownRenderer < Redcarpet::Render::HTML
    def link(link, title, alt_text)
      "<a target=\"_blank\" href=\"#{link}\">#{alt_text}</a>"
    end
    def autolink(link, link_type)
      "<a target=\"_blank\" href=\"#{link}\">#{link}</a>"
    end
  end

  def renderer
    Redcarpet::Markdown.new(MarkdownRenderer.new(hard_wrap: true, filter_html: true), tables: true, autolink: true)
  end
end
