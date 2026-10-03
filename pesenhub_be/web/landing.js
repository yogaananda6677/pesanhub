(function () {
  'use strict';

  // Mobile Navigation Toggle
  const mobileToggle = document.getElementById('mobile-toggle');
  const mobileMenu = document.getElementById('mobile-menu');

  if (mobileToggle && mobileMenu) {
    mobileToggle.addEventListener('click', () => {
      mobileMenu.classList.toggle('open');
      const isOpen = mobileMenu.classList.contains('open');
      mobileToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      mobileToggle.textContent = isOpen ? '✕' : '☰';
    });

    mobileMenu.querySelectorAll('.nav-link, .btn').forEach((link) => {
      link.addEventListener('click', () => {
        mobileMenu.classList.remove('open');
        mobileToggle.setAttribute('aria-expanded', 'false');
        mobileToggle.textContent = '☰';
      });
    });
  }

  // Interactive Menu Category Tabs
  const tabBtns = document.querySelectorAll('.menu-tab-btn');
  const catGroups = document.querySelectorAll('.menu-category-group');

  tabBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetCategory = btn.getAttribute('data-category');

      tabBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');

      catGroups.forEach((group) => {
        const groupCat = group.getAttribute('data-category');
        if (targetCategory === 'all' || groupCat === targetCategory) {
          group.style.display = 'block';
        } else {
          group.style.display = 'none';
        }
      });
    });
  });

  // Lightbox Flyer Modal
  const lightboxModal = document.getElementById('lightbox-modal');
  const lightboxImg = document.getElementById('lightbox-img');
  const lightboxClose = document.getElementById('lightbox-close');

  function openLightbox(src, alt) {
    if (!lightboxModal || !lightboxImg) return;
    lightboxImg.src = src;
    lightboxImg.alt = alt || 'Poster Menu Martabak Jenggirat';
    lightboxModal.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    if (!lightboxModal) return;
    lightboxModal.classList.remove('open');
    document.body.style.overflow = '';
  }

  document.querySelectorAll('[data-lightbox-src]').forEach((el) => {
    el.addEventListener('click', (e) => {
      e.preventDefault();
      const src = el.getAttribute('data-lightbox-src');
      const alt = el.getAttribute('data-lightbox-alt') || 'Poster Menu';
      openLightbox(src, alt);
    });
  });

  if (lightboxClose) {
    lightboxClose.addEventListener('click', closeLightbox);
  }

  if (lightboxModal) {
    lightboxModal.addEventListener('click', (e) => {
      if (e.target === lightboxModal) {
        closeLightbox();
      }
    });
  }

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && lightboxModal && lightboxModal.classList.contains('open')) {
      closeLightbox();
    }
  });

  // Header scroll shadow effect
  const siteHeader = document.querySelector('.site-header');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 20) {
      siteHeader.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.08)';
    } else {
      siteHeader.style.boxShadow = 'var(--shadow-sm)';
    }
  });
})();
