module.exports = {
  future: {
    hoverOnlyWhenSupported: true
  },
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: [
      {
        docuseal: {
          'color-scheme': 'light',
          // J.D. Pools brand (jdpoolstech design-system/brand-tokens.css). See JDPOOLS.md.
          primary: '#e6e8f0',
          secondary: '#0095da',
          accent: '#f6821f',
          neutral: '#203a71',
          'neutral-content': '#ffffff',
          'base-100': '#f4f5f9',
          'base-200': '#e6e8f0',
          'base-300': '#d8dbe8',
          'base-content': '#203a71',
          '--rounded-btn': '0.625rem',
          '--rounded-box': '0.875rem',
          '--tab-border': '2px',
          '--tab-radius': '.5rem'
        }
      }
    ]
  }
}
