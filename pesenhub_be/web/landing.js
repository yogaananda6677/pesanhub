(function () {
  'use strict';

  // Mobile Navigation Toggle
  const mobileToggle = document.getElementById('mobile-toggle');
  const mobileMenu = document.getElementById('mobile-menu');

  if (mobileToggle && mobileMenu) {
    const toggleIconUse = mobileToggle.querySelector('use');
    mobileToggle.addEventListener('click', () => {
      mobileMenu.classList.toggle('open');
      const isOpen = mobileMenu.classList.contains('open');
      mobileToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      if (toggleIconUse) {
        toggleIconUse.setAttribute('href', isOpen ? '#icon-close' : '#icon-menu');
      }
    });

    mobileMenu.querySelectorAll('.nav-link, .btn').forEach((link) => {
      link.addEventListener('click', () => {
        mobileMenu.classList.remove('open');
        mobileToggle.setAttribute('aria-expanded', 'false');
        if (toggleIconUse) {
          toggleIconUse.setAttribute('href', '#icon-menu');
        }
      });
    });
  }

  // Interactive Menu Category Tabs
  const tabBtns = document.querySelectorAll('.menu-tab-btn');
  const catSections = document.querySelectorAll('.menu-category-section');

  tabBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetCategory = btn.getAttribute('data-category');

      tabBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');

      catSections.forEach((section) => {
        const sectionCat = section.getAttribute('data-category');
        if (targetCategory === 'all' || sectionCat === targetCategory) {
          section.style.display = 'block';
        } else {
          section.style.display = 'none';
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
