// Bulkrax Utilities - Reusable helper functions
// Used across Bulkrax JavaScript modules

; (function () {
  'use strict'

  // Create namespace
  window.BulkraxUtils = window.BulkraxUtils || {}

  // ============================================================================
  // HTML & STRING UTILITIES
  // ============================================================================

  /**
   * Escape HTML to prevent XSS attacks
   * @param {string} unsafe - Untrusted user input
   * @returns {string} HTML-safe string
   */
  function escapeHtml(unsafe) {
    if (!unsafe) return ''
    return unsafe
      .toString()
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;')
  }

  // ============================================================================
  // FILE UTILITIES
  // ============================================================================

  /**
   * Format file size in human-readable format
   * @param {number} bytes - File size in bytes
   * @returns {string} Formatted size (e.g., "1.5 MB")
   */
  function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    var k = 1024
    var sizes = ['Bytes', 'KB', 'MB', 'GB']
    var i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i]
  }

  // ============================================================================
  // DATA NORMALIZATION
  // ============================================================================

  /**
   * Normalize boolean or string boolean to actual boolean
   * Handles both boolean types and string representations
   * @param {boolean|string} value - Value to normalize
   * @returns {boolean|null} true, false, or null if indeterminate
   */
  function normalizeBoolean(value) {
    if (value === true || value === 'true') return true
    if (value === false || value === 'false') return false
    return null
  }

  // ============================================================================
  // INTERNATIONALIZATION
  // ============================================================================

  /**
   * Look up a translation key from BulkraxI18n and interpolate variables.
   * Falls back to the key name if not found.
   * @param {string} key - Translation key (e.g. 'file_upload_error')
   * @param {Object} [vars] - Interpolation variables (e.g. {count: 5})
   * @returns {string} Translated and interpolated string
   */
  function t(key, vars) {
    var translations = window.BulkraxI18n || {}
    var text = translations[key]
    if (text == null) return key
    if (vars) {
      Object.keys(vars).forEach(function (k) {
        text = text.replace(new RegExp('%\\{' + k + '\\}', 'g'), vars[k])
      })
    }
    return text
  }

  // ============================================================================
  // PUBLIC API
  // ============================================================================

  window.BulkraxUtils = {
    escapeHtml: escapeHtml,
    formatFileSize: formatFileSize,
    normalizeBoolean: normalizeBoolean,
    t: t
  }
})()
