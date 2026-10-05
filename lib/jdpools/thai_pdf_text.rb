# frozen_string_literal: true

module Jdpools
  # Correct placement of Thai vowel and tone marks in generated PDFs.
  #
  # HexaPDF does no complex-script shaping, so a tone mark over an upper vowel (ที่, ตั้ง) collides
  # with it. This applies the approach Thai PDF tools without a shaping engine use: draw Thai text
  # in a font that carries the Microsoft-convention pre-positioned mark glyphs (Unicode private-use
  # U+F700-U+F71A; the TLWG fonts do) and pick the right variant from the surrounding characters.
  #
  # Each substituted glyph keeps the original character as its text, so copying or searching the
  # PDF still yields ordinary Thai.
  module ThaiPdfText
    FONT_DIR = Rails.root.join('config/jdpools/fonts')
    FONT_PATH = FONT_DIR.join('Laksaman.ttf').to_s
    FONT_BOLD_PATH = FONT_DIR.join('Laksaman-Bold.ttf').to_s

    THAI = /[฀-๿]/

    ASCENDER_CONSONANTS = [0x0E1B, 0x0E1D, 0x0E1F, 0x0E2C].freeze # ป ฝ ฟ ฬ
    DESCENDER_CONSONANTS = [0x0E0E, 0x0E0F, 0x0E24, 0x0E26].freeze # ฎ ฏ ฤ ฦ
    DESCENDERLESS = { 0x0E0D => 0xF70F, 0x0E10 => 0xF700 }.freeze # ญ ฐ without the tail
    SARA_AM = 0x0E33

    # Upper vowels moved left over a tall consonant.
    UPPER_VOWEL_LEFT = {
      0x0E31 => 0xF710, 0x0E34 => 0xF701, 0x0E35 => 0xF702, 0x0E36 => 0xF703,
      0x0E37 => 0xF704, 0x0E47 => 0xF712, 0x0E4D => 0xF711
    }.freeze

    TONE_MARKS = (0x0E48..0x0E4C)
    # Tone marks: the font's default glyph sits high, above an upper vowel.
    TONE_LOW = TONE_MARKS.index_with { |c| c - 0x0E48 + 0xF70A }        # directly on the consonant
    TONE_LOW_LEFT = TONE_MARKS.index_with { |c| c - 0x0E48 + 0xF705 }   # ... of a tall consonant
    TONE_HIGH_LEFT = TONE_MARKS.index_with { |c| c - 0x0E48 + 0xF713 }  # over an upper vowel on a tall consonant

    LOWER_VOWEL_LOW = { 0x0E38 => 0xF718, 0x0E39 => 0xF719, 0x0E3A => 0xF71A }.freeze

    module_function

    def thai?(text)
      text.is_a?(String) && text.match?(THAI)
    end

    def available?
      File.exist?(FONT_PATH) && File.exist?(FONT_BOLD_PATH)
    end

    # [[display_codepoint, original_character], ...] for the given text.
    # rubocop:disable Metrics
    def positioned(text)
      result = []
      base = nil
      base_index = nil
      upper = false
      codepoints = text.codepoints

      codepoints.each_with_index do |c, i|
        display = c

        if c.between?(0x0E01, 0x0E2E)
          base = c
          base_index = result.size
          upper = false
        elsif UPPER_VOWEL_LEFT.key?(c)
          display = UPPER_VOWEL_LEFT[c] if ASCENDER_CONSONANTS.include?(base)
          upper = true
        elsif TONE_MARKS.cover?(c)
          high = upper || codepoints[i + 1] == SARA_AM
          tall = ASCENDER_CONSONANTS.include?(base)

          display =
            if high
              tall ? TONE_HIGH_LEFT[c] : c
            else
              tall ? TONE_LOW_LEFT[c] : TONE_LOW[c]
            end
        elsif LOWER_VOWEL_LOW.key?(c)
          if DESCENDER_CONSONANTS.include?(base)
            display = LOWER_VOWEL_LOW[c]
          elsif DESCENDERLESS.key?(base) && base_index
            result[base_index] = [DESCENDERLESS[base], result[base_index][1]]
          end
        elsif !(0x0E00..0x0E7F).cover?(c)
          base = nil
          upper = false
        end

        result << [display, +'' << c]
      end

      result
    end
    # rubocop:enable Metrics

    def glyphs(text, font)
      cmap = font.wrapped_font[:cmap].preferred_table

      positioned(text).map do |display, original|
        if display == original.ord
          font.decode_codepoint(display)
        elsif (gid = cmap[display])
          font.glyph(gid, original)
        else
          font.decode_codepoint(original.ord)
        end
      end
    end

    # The Thai font to use in place of the given font wrapper, in the same document.
    def font_for(font_wrapper)
      return unless available?

      document = font_wrapper.pdf_object.document
      bold = font_wrapper.pdf_object[:BaseFont].to_s.match?(/bold/i)

      document.fonts.add(bold ? FONT_BOLD_PATH : FONT_PATH)
    end

    # Prepended to HexaPDF::Layout::TextFragment's singleton. DocuSeal draws field values and
    # signature stamps through TextFragment.create, and lays out the audit trail through
    # create_with_fallback_glyphs (whose fallback silently drops Thai, since the audit trail uses
    # Helvetica); both route Thai text here.
    module TextFragmentPatch
      def create_with_fallback_glyphs(text, style, &)
        return super unless Jdpools::ThaiPdfText.thai?(text) && Jdpools::ThaiPdfText.available?

        [create(text, style)]
      end

      def create(text, style)
        return super unless Jdpools::ThaiPdfText.thai?(text)

        style = HexaPDF::Layout::Style.create(style)
        thai_font = Jdpools::ThaiPdfText.font_for(style.font)

        return super unless thai_font

        thai_style = style.dup.font(thai_font)

        HexaPDF::Layout::TextShaper.new.shape_text(new(Jdpools::ThaiPdfText.glyphs(text, thai_font), thai_style))
      end
    end
  end
end
