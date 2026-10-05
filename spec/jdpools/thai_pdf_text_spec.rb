# frozen_string_literal: true

RSpec.describe Jdpools::ThaiPdfText do
  def displayed(text)
    described_class.positioned(text).map { |display, _| display }
  end

  def hex(*codepoints)
    codepoints.map { |c| format('U+%04X', c) }
  end

  describe '.positioned' do
    it 'keeps a tone mark high when an upper vowel is below it (ที่)' do
      expect(hex(*displayed('ที่'))).to eq(hex(0x0E17, 0x0E35, 0x0E48))
    end

    it 'drops a tone mark onto a consonant with no upper vowel (ก่)' do
      expect(hex(*displayed('ก่'))).to eq(hex(0x0E01, 0xF70A))
    end

    it 'shifts marks left over a tall consonant (ปั้น, ป่, ปี่)' do
      expect(hex(*displayed('ปั้น'))).to eq(hex(0x0E1B, 0xF710, 0xF714, 0x0E19))
      expect(hex(*displayed('ป่'))).to eq(hex(0x0E1B, 0xF705))
      expect(hex(*displayed('ปี่'))).to eq(hex(0x0E1B, 0xF702, 0xF713))
    end

    it 'keeps the tone mark high before sara am (น้ำ)' do
      expect(hex(*displayed('น้ำ'))).to eq(hex(0x0E19, 0x0E49, 0x0E33))
    end

    it 'drops a lower vowel under a consonant with a tail (ฎุ) and removes the tail of ญ, ฐ' do
      expect(hex(*displayed('ฎุ'))).to eq(hex(0x0E0E, 0xF718))
      expect(hex(*displayed('ญู'))).to eq(hex(0xF70F, 0x0E39))
      expect(hex(*displayed('ฐุ'))).to eq(hex(0xF700, 0x0E38))
      expect(hex(*displayed('ฐาน'))).to eq(hex(0x0E10, 0x0E32, 0x0E19))
    end

    it 'remembers the original characters' do
      expect(described_class.positioned('ปั้น').map(&:last).join).to eq('ปั้น')
    end

    it 'does not carry a base consonant across non-Thai text' do
      expect(hex(*displayed('ป ่'))).to eq(hex(0x0E1B, 0x20, 0xF70A))
    end
  end

  describe 'in a generated PDF' do
    let(:document) { HexaPDF::Document.new }
    let(:helvetica) { document.fonts.add('Helvetica') }

    it 'draws Thai in the bundled Thai font with positioned glyphs that still read as Thai' do
      fragment = HexaPDF::Layout::TextFragment.create('ก่', font: helvetica, font_size: 12)
      tone = fragment.items.last

      expect(fragment.style.font.pdf_object[:BaseFont].to_s).to include('Laksaman')
      expect(tone.id).to eq(fragment.style.font.wrapped_font[:cmap].preferred_table[0xF70A])
      expect(tone.str).to eq('่')
    end

    it 'uses the bold Thai font for bold text' do
      bold = document.fonts.add('Helvetica', variant: :bold)

      fragment = HexaPDF::Layout::TextFragment.create('ที่', font: bold, font_size: 12)

      expect(fragment.style.font.pdf_object[:BaseFont].to_s).to include('Laksaman-Bold')
    end

    it 'keeps Thai that the layout engine would otherwise drop for a font without Thai glyphs' do
      fragments = HexaPDF::Layout::TextFragment.create_with_fallback_glyphs('สมชาย ปั้นน้ำใจ', font: helvetica,
                                                                                               font_size: 12) { [] }

      expect(fragments.size).to eq(1)
      expect(fragments.first.items.filter_map { |g| g.str if g.respond_to?(:str) }.join).to eq('สมชาย ปั้นน้ำใจ')
    end

    it 'leaves non-Thai text alone' do
      fragment = HexaPDF::Layout::TextFragment.create('Phuket', font: helvetica, font_size: 12)

      expect(fragment.style.font).to eq(helvetica)
    end
  end
end
