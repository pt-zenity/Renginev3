/**
 * reNgine-ng Professional UI - Real-time Enhancement Script
 * Handles: animated counters, live indicators, chart enhancements,
 *          page-load animations, terminal effects, activity feeds
 */
(function() {
  'use strict';

  /* ══════════════════════════════════════════════
     PAGE LOAD ANIMATION
  ══════════════════════════════════════════════ */
  function initPageLoad() {
    const bar = document.getElementById('page-load-bar');
    if (!bar) return;

    let w = 0;
    const fast = setInterval(() => {
      w += Math.random() * 15;
      if (w >= 90) { clearInterval(fast); return; }
      bar.style.width = w + '%';
    }, 80);

    window.addEventListener('load', () => {
      clearInterval(fast);
      bar.style.width = '100%';
      bar.style.transition = 'width 0.3s ease';
      setTimeout(() => {
        bar.style.opacity = '0';
        bar.style.transition = 'opacity 0.4s ease';
        setTimeout(() => bar.remove(), 400);
      }, 300);
    });
  }

  /* ══════════════════════════════════════════════
     ANIMATED NUMBER COUNTER
  ══════════════════════════════════════════════ */
  function animateCounter(el, target, duration) {
    if (!el) return;
    const start     = 0;
    const startTime = performance.now();
    const isFloat   = String(target).includes('.');
    const decimals  = isFloat ? String(target).split('.')[1].length : 0;

    function easeOutCubic(t) {
      return 1 - Math.pow(1 - t, 3);
    }

    function step(now) {
      const elapsed  = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const eased    = easeOutCubic(progress);
      const value    = start + (target - start) * eased;

      el.textContent = isFloat
        ? value.toFixed(decimals)
        : Math.round(value).toLocaleString();

      if (progress < 1) {
        requestAnimationFrame(step);
      } else {
        el.textContent = isFloat
          ? target.toFixed(decimals)
          : Number(target).toLocaleString();
      }
    }

    requestAnimationFrame(step);
  }

  function initCounters() {
    // data-plugin="counterup" elements (existing)
    const counterEls = document.querySelectorAll('[data-plugin="counterup"]');
    counterEls.forEach(el => {
      const raw    = el.textContent.replace(/,/g, '').trim();
      const target = parseFloat(raw);
      if (!isNaN(target)) {
        el.textContent = '0';
        animateCounter(el, target, 1400);
      }
    });

    // Also target h2 elements with numeric content in stat cards
    document.querySelectorAll('.card-body h2').forEach(el => {
      if (!el.querySelector('[data-plugin]')) {
        const raw    = el.textContent.replace(/,/g, '').trim();
        const target = parseFloat(raw);
        if (!isNaN(target) && target > 0) {
          el.dataset.originalText = el.textContent;
          const span = document.createElement('span');
          span.textContent = '0';
          el.textContent   = '';
          el.appendChild(span);
          animateCounter(span, target, 1200);
        }
      }
    });
  }

  /* ══════════════════════════════════════════════
     FADE-IN CARDS ON LOAD
  ══════════════════════════════════════════════ */
  function initCardAnimations() {
    const cards = document.querySelectorAll('.card');
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry, i) => {
        if (entry.isIntersecting) {
          entry.target.style.opacity    = '0';
          entry.target.style.transform  = 'translateY(20px)';
          entry.target.style.transition = `opacity 0.5s ease ${i * 0.04}s, transform 0.5s ease ${i * 0.04}s`;
          requestAnimationFrame(() => {
            entry.target.style.opacity   = '1';
            entry.target.style.transform = 'translateY(0)';
          });
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.05 });

    cards.forEach(c => observer.observe(c));
  }

  /* ══════════════════════════════════════════════
     LIVE SCAN COUNTER IN NAVBAR
  ══════════════════════════════════════════════ */
  function initLiveScanBadge() {
    const counter = document.getElementById('current_scan_counter');
    if (!counter) return;

    function updateBadge() {
      const n = parseInt(counter.textContent, 10) || 0;
      const badge = counter.closest('.noti-icon-badge');
      if (!badge) return;

      if (n > 0) {
        badge.style.display = '';
        badge.style.boxShadow = '0 0 10px rgba(239,68,68,0.6)';
      } else {
        badge.style.display = 'none';
      }
    }

    // Observe mutations (the scan status function updates it)
    const observer = new MutationObserver(updateBadge);
    observer.observe(counter, { childList: true, subtree: true, characterData: true });
    updateBadge();
  }

  /* ══════════════════════════════════════════════
     SEVERITY BADGE ENHANCEMENT
  ══════════════════════════════════════════════ */
  function enhanceSeverityBadges() {
    const mapping = {
      'Critical': { bg: 'rgba(255,71,87,0.15)',  color: '#ff4757', border: 'rgba(255,71,87,0.3)',  glow: 'rgba(255,71,87,0.2)' },
      'High':     { bg: 'rgba(255,107,53,0.15)', color: '#ff6b35', border: 'rgba(255,107,53,0.3)', glow: null },
      'Medium':   { bg: 'rgba(255,165,2,0.15)',  color: '#ffa502', border: 'rgba(255,165,2,0.3)',  glow: null },
      'Low':      { bg: 'rgba(236,204,104,0.15)',color: '#eccc68', border: 'rgba(236,204,104,0.3)',glow: null },
      'Info':     { bg: 'rgba(112,161,255,0.15)',color: '#70a1ff', border: 'rgba(112,161,255,0.3)',glow: null },
    };

    document.querySelectorAll('.badge').forEach(badge => {
      const text = badge.textContent.trim();
      if (mapping[text]) {
        const m = mapping[text];
        badge.style.background   = m.bg;
        badge.style.color        = m.color;
        badge.style.border       = `1px solid ${m.border}`;
        badge.style.borderRadius = '20px';
        if (m.glow) badge.style.boxShadow = `0 0 8px ${m.glow}`;
      }
    });
  }

  /* ══════════════════════════════════════════════
     STAT CARD GLOWING BORDER BASED ON CRITICAL COUNT
  ══════════════════════════════════════════════ */
  function colorizeStatCards() {
    // Find vuln card and add glow if critical > 0
    const criticalEl = document.querySelector('.text-danger h2, h2.text-danger');
    if (criticalEl) {
      const val = parseInt(criticalEl.textContent.replace(/,/g, ''), 10);
      if (val > 0) {
        const card = criticalEl.closest('.card');
        if (card) {
          card.style.borderColor = 'rgba(239,68,68,0.35)';
          card.style.boxShadow   = '0 0 25px rgba(239,68,68,0.12), 0 8px 24px rgba(0,0,0,0.5)';
        }
      }
    }
  }

  /* ══════════════════════════════════════════════
     TABLE ROW HOVER HIGHLIGHT (keyboard accessible)
  ══════════════════════════════════════════════ */
  function enhanceTables() {
    document.querySelectorAll('table.dataTable, .table').forEach(tbl => {
      tbl.querySelectorAll('tbody tr').forEach(row => {
        row.addEventListener('mouseenter', () => {
          row.style.transition = 'background 0.15s ease';
          row.style.background = 'rgba(59,130,246,0.05)';
        });
        row.addEventListener('mouseleave', () => {
          row.style.background = '';
        });
      });
    });
  }

  /* ══════════════════════════════════════════════
     SEARCH INPUT – LIVE GLOW
  ══════════════════════════════════════════════ */
  function enhanceSearch() {
    const searchInput = document.getElementById('top-search');
    if (!searchInput) return;

    searchInput.addEventListener('focus', () => {
      const wrapper = searchInput.closest('.app-search-box, .input-group');
      if (wrapper) {
        wrapper.style.transition = 'box-shadow 0.25s ease';
        wrapper.style.boxShadow  = '0 0 0 3px rgba(59,130,246,0.2)';
      }
    });

    searchInput.addEventListener('blur', () => {
      const wrapper = searchInput.closest('.app-search-box, .input-group');
      if (wrapper) wrapper.style.boxShadow = '';
    });
  }

  /* ══════════════════════════════════════════════
     ACTIVITY FEED ICON ENHANCEMENT
  ══════════════════════════════════════════════ */
  function enhanceActivityFeed() {
    // Replace mdi circle-outline icons with fa icons per status
    document.querySelectorAll('.track-order-list .mdi-checkbox-blank-circle-outline').forEach(icon => {
      const li = icon.closest('.d-flex');
      if (!li) return;

      const statusClass = icon.className;
      icon.className = 'fa fa-circle-dot me-2 mt-1';
      if      (statusClass.includes('text-danger'))  icon.style.color = '#ef4444';
      else if (statusClass.includes('text-info'))    icon.style.color = '#3b82f6';
      else if (statusClass.includes('text-success')) icon.style.color = '#10b981';
    });
  }

  /* ══════════════════════════════════════════════
     AUTO-REFRESH LIVE INDICATOR ON DASHBOARD
  ══════════════════════════════════════════════ */
  function addLiveIndicator() {
    const titleBox = document.querySelector('.page-title-box');
    if (!titleBox || document.querySelector('.live-indicator-injected')) return;

    const scanCounter = document.getElementById('current_scan_counter');
    const count = scanCounter ? parseInt(scanCounter.textContent, 10) || 0 : 0;

    if (count > 0) {
      const indicator = document.createElement('span');
      indicator.className = 'live-indicator-injected ms-3 scan-running-indicator';
      indicator.innerHTML = `${count} Scan${count > 1 ? 's' : ''} Running`;
      const title = titleBox.querySelector('h4.page-title');
      if (title) title.after(indicator);
    }
  }

  /* ══════════════════════════════════════════════
     COPY-TO-CLIPBOARD HELPER (adds copy btn to code blocks)
  ══════════════════════════════════════════════ */
  function addCopyButtons() {
    document.querySelectorAll('pre').forEach(pre => {
      if (pre.querySelector('.copy-btn')) return;
      const btn = document.createElement('button');
      btn.className   = 'copy-btn btn btn-xs btn-secondary';
      btn.textContent = 'Copy';
      btn.style.cssText = 'position:absolute;top:8px;right:8px;opacity:0.7;';
      pre.style.position = 'relative';
      pre.appendChild(btn);

      btn.addEventListener('click', () => {
        const code = pre.querySelector('code');
        const text = (code || pre).textContent;
        navigator.clipboard.writeText(text).then(() => {
          btn.textContent = 'Copied!';
          btn.style.background = 'rgba(16,185,129,0.2)';
          btn.style.color = '#10b981';
          setTimeout(() => {
            btn.textContent = 'Copy';
            btn.style.background = '';
            btn.style.color = '';
          }, 2000);
        });
      });
    });
  }

  /* ══════════════════════════════════════════════
     NAVBAR SCROLL SHADOW
  ══════════════════════════════════════════════ */
  function initNavbarScroll() {
    const navbar = document.querySelector('.navbar-custom');
    if (!navbar) return;

    let scrolled = false;
    window.addEventListener('scroll', () => {
      if (window.scrollY > 10 && !scrolled) {
        navbar.style.boxShadow = '0 4px 30px rgba(0,0,0,0.7)';
        scrolled = true;
      } else if (window.scrollY <= 10 && scrolled) {
        navbar.style.boxShadow = '0 4px 30px rgba(0,0,0,0.5)';
        scrolled = false;
      }
    }, { passive: true });
  }

  /* ══════════════════════════════════════════════
     APEXCHARTS DARK THEME PATCH
  ══════════════════════════════════════════════ */
  function patchApexChartsTheme() {
    // Wait for ApexCharts to render and patch tooltips/backgrounds
    const patchCSS = document.createElement('style');
    patchCSS.textContent = `
      .apexcharts-canvas { background: transparent !important; }
      .apexcharts-theme-light .apexcharts-tooltip {
        background: #111827 !important;
        border: 1px solid rgba(59,130,246,0.2) !important;
        color: #e2e8f0 !important;
        border-radius: 8px !important;
        box-shadow: 0 10px 30px rgba(0,0,0,0.5) !important;
      }
      .apexcharts-theme-light .apexcharts-tooltip-title {
        background: rgba(59,130,246,0.1) !important;
        border-bottom: 1px solid rgba(59,130,246,0.2) !important;
        color: #e2e8f0 !important;
      }
      .apexcharts-legend-text { color: #94a3b8 !important; font-size: 12px !important; }
      .apexcharts-gridline { stroke: rgba(59,130,246,0.08) !important; }
      .apexcharts-xaxis-label tspan,
      .apexcharts-yaxis-label tspan { fill: #64748b !important; }
    `;
    document.head.appendChild(patchCSS);
  }

  /* ══════════════════════════════════════════════
     DATATABLE DARK THEME PATCH
  ══════════════════════════════════════════════ */
  function patchDataTableTheme() {
    if (!window.$) return;

    $(document).on('draw.dt', function() {
      // Style the empty rows message
      document.querySelectorAll('.dataTables_empty').forEach(el => {
        el.style.color = '#64748b';
        el.style.padding = '30px';
        el.style.fontStyle = 'italic';
      });
    });
  }

  /* ══════════════════════════════════════════════
     TOOLTIPS – DARK OVERRIDE
  ══════════════════════════════════════════════ */
  function patchBootstrapTooltips() {
    if (!window.bootstrap) return;
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      const tt = bootstrap.Tooltip.getInstance(el);
      if (tt) {
        el.addEventListener('shown.bs.tooltip', () => {
          const tip = document.querySelector('.tooltip');
          if (tip) {
            tip.style.cssText = `
              background: #111827 !important;
              border: 1px solid rgba(59,130,246,0.2) !important;
              border-radius: 6px !important;
              font-size: 12px !important;
            `;
          }
        });
      }
    });
  }

  /* ══════════════════════════════════════════════
     SHORTCUT KEYS
  ══════════════════════════════════════════════ */
  function initKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
      // Ctrl/Cmd + K → focus search
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        const search = document.getElementById('top-search');
        if (search) {
          search.focus();
          search.select();
        }
      }
    });
  }

  /* ══════════════════════════════════════════════
     MOBILE NAV DRAWER
     Handles: body scroll lock, overlay click-to-close,
     hamburger ↔ X animation, swipe-down to close
  ══════════════════════════════════════════════ */
  function initMobileNav() {
    const mobileMenu = document.getElementById('mobileNavMenu');
    const hamburger  = document.getElementById('mobileHamburger');
    if (!mobileMenu) return;

    /* ── Scroll-lock helpers ───────────────────────────────── */
    let _scrollY = 0;

    function lockBody() {
      _scrollY = window.scrollY;
      document.body.style.top = `-${_scrollY}px`;
      document.body.classList.add('mobile-nav-open');
    }

    function unlockBody() {
      document.body.classList.remove('mobile-nav-open');
      document.body.style.top = '';
      window.scrollTo({ top: _scrollY, behavior: 'instant' });
    }

    /* ── Bootstrap collapse events ─────────────────────────── */
    mobileMenu.addEventListener('show.bs.collapse',  lockBody);
    mobileMenu.addEventListener('hide.bs.collapse',  unlockBody);
    mobileMenu.addEventListener('hidden.bs.collapse', () => {
      // Reset hamburger aria state in case Bootstrap missed it
      if (hamburger) hamburger.setAttribute('aria-expanded', 'false');
    });

    /* ── Click on overlay (body::after) closes drawer ─────── */
    document.addEventListener('click', function(e) {
      if (!document.body.classList.contains('mobile-nav-open')) return;
      // If click is outside the navbar-custom (where menu lives), close
      const navbar = document.querySelector('.navbar-custom');
      const drawer = mobileMenu;
      if (!navbar) return;
      if (!navbar.contains(e.target) && !drawer.contains(e.target)) {
        if (window.bootstrap && window.bootstrap.Collapse) {
          const bsCollapse = window.bootstrap.Collapse.getInstance(mobileMenu);
          if (bsCollapse) bsCollapse.hide();
        }
      }
    });

    /* ── Close on Escape key ────────────────────────────────── */
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && document.body.classList.contains('mobile-nav-open')) {
        if (window.bootstrap && window.bootstrap.Collapse) {
          const bsCollapse = window.bootstrap.Collapse.getInstance(mobileMenu);
          if (bsCollapse) bsCollapse.hide();
        }
      }
    });

    /* ── Auto-close drawer when a nav link is clicked ─────── */
    mobileMenu.querySelectorAll('.mobile-nav-link:not(.mobile-nav-toggle), .mobile-nav-sublink, .mobile-nav-extra-btn').forEach(function(el) {
      el.addEventListener('click', function() {
        // Small delay so the click registers before hiding
        setTimeout(function() {
          if (window.bootstrap && window.bootstrap.Collapse) {
            const bsCollapse = window.bootstrap.Collapse.getInstance(mobileMenu);
            if (bsCollapse) bsCollapse.hide();
          }
        }, 120);
      });
    });

    /* ── Touch swipe-down to close ──────────────────────────── */
    let touchStartY = 0;
    mobileMenu.addEventListener('touchstart', function(e) {
      touchStartY = e.touches[0].clientY;
    }, { passive: true });
    mobileMenu.addEventListener('touchend', function(e) {
      const diff = e.changedTouches[0].clientY - touchStartY;
      if (diff > 60) { // swiped down 60px
        if (window.bootstrap && window.bootstrap.Collapse) {
          const bsCollapse = window.bootstrap.Collapse.getInstance(mobileMenu);
          if (bsCollapse) bsCollapse.hide();
        }
      }
    }, { passive: true });
  }

  /* ══════════════════════════════════════════════
     MOBILE SUBMENU TOGGLE (legacy — kept for compat)
  ══════════════════════════════════════════════ */
  function initMobileSubmenu() {
    document.querySelectorAll('.mobile-submenu-header').forEach(header => {
      header.addEventListener('click', () => {
        const submenu = header.nextElementSibling;
        if (!submenu || !submenu.classList.contains('mobile-submenu')) return;
        const isOpen = submenu.classList.contains('show');
        // Close all
        document.querySelectorAll('.mobile-submenu.show').forEach(m => m.classList.remove('show'));
        document.querySelectorAll('.mobile-submenu-header.active').forEach(h => h.classList.remove('active'));
        if (!isOpen) {
          submenu.classList.add('show');
          header.classList.add('active');
        }
      });
    });
  }

  /* ══════════════════════════════════════════════
     SNACKBAR DARK STYLE INJECTION
  ══════════════════════════════════════════════ */
  function patchSnackbar() {
    // Override snackbar default white style to match dark theme
    const style = document.createElement('style');
    style.textContent = `
      #snackbar-container .snackbar {
        background: #1e293b !important;
        border: 1px solid rgba(59,130,246,0.2) !important;
        border-radius: 10px !important;
        box-shadow: 0 10px 30px rgba(0,0,0,0.5) !important;
        color: #e2e8f0 !important;
        font-family: 'Inter', sans-serif !important;
        font-size: 0.875rem !important;
      }
    `;
    document.head.appendChild(style);
  }

  /* ══════════════════════════════════════════════
     VULN HIGHLIGHT — flicker critical badges
  ══════════════════════════════════════════════ */
  function highlightCriticalBadges() {
    document.querySelectorAll('.badge-critical, .badge.badge-critical').forEach(badge => {
      badge.style.animation = 'none';
      // subtle attention pulse
      const pulse = [
        { boxShadow: '0 0 6px rgba(255,71,87,0.3)' },
        { boxShadow: '0 0 14px rgba(255,71,87,0.6)' },
        { boxShadow: '0 0 6px rgba(255,71,87,0.3)' },
      ];
      if (badge.animate) {
        badge.animate(pulse, { duration: 2000, iterations: Infinity, easing: 'ease-in-out' });
      }
    });
  }

  /* ══════════════════════════════════════════════
     INIT ALL
  ══════════════════════════════════════════════ */
  function init() {
    initPageLoad();
    patchApexChartsTheme();
    patchSnackbar();
    initNavbarScroll();
    initKeyboardShortcuts();
    initMobileNav();
    initMobileSubmenu();

    // DOM-ready tasks
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', domReady);
    } else {
      domReady();
    }

    // After full page + scripts
    window.addEventListener('load', () => {
      setTimeout(() => {
        initCounters();
        enhanceSeverityBadges();
        colorizeStatCards();
        enhanceTables();
        enhanceActivityFeed();
        addCopyButtons();
        highlightCriticalBadges();
        addLiveIndicator();
        patchBootstrapTooltips();
        patchDataTableTheme();
      }, 100);
    });
  }

  function domReady() {
    initCardAnimations();
    enhanceSearch();
  }

  // Kick off
  init();

})();
