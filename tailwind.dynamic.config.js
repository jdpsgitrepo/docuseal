const path = require('path')

module.exports = {
  future: {
    hoverOnlyWhenSupported: true
  },
  content: [
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_area.vue'),
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_section.vue')
  ],
  theme: {
    extend: {
      colors: {
        'base-100': '#f4f5f9',
        'base-200': '#e6e8f0',
        'base-300': '#d8dbe8',
        'base-content': '#203a71'
      }
    }
  }
}
