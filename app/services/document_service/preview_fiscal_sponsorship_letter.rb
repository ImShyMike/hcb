module DocumentService
  class PreviewFiscalSponsorshipLetter
    def initialize(event:)
      @event = event
    end

    def run
      IO.popen(cmd, err: File::NULL).read
    end

    private

    def pdf_string
      @pdf_string ||= ActionController::Base.new.render_to_string pdf: 'fiscal_sponsorship_letter', template: 'documents/fiscal_sponsorship_letter.pdf.erb', encoding: 'UTF-8', locals: { :@event => @event }
    end

    def input
      @input ||= begin
        input = Tempfile.new(['fiscal_sponsorship_letter_preview', '.pdf'])
        input.binmode
        input.write(pdf_string)
        input.rewind

        input
      end
    end

    def cmd
      ['mutool', 'draw', '-F', 'png', '-o', '-', input.path, '1']
    end
  end
end
