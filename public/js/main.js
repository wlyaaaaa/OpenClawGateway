/* Main script for wlyaaaaaa /吴乐阳 personal site */
document.addEventListener('DOMContentLoaded', () => {
  // nav scroll highlight
  const links = document.querySelectorAll('.nav-links .link, .nav-links a');
  const updateActiveLink = () => {
    let cur = '';
    document.querySelectorAll('section[id]').forEach(s => {
      if (window.scrollY >= s.offsetTop - 120) cur = '#' + s.id;
    });
    links.forEach(a => {
      a.classList.remove('active');
      if (a.getAttribute('href') === cur || (cur === '' && a.getAttribute('href') === '#')) {
        a.classList.add('active');
      }
    });
  };
  if (links.length) {
    window.addEventListener('scroll', updateActiveLink, { passive: true });
    updateActiveLink();
  }

  // fade-in on scroll
  const fadeItems = document.querySelectorAll('.fi, .fiv');
  if ('IntersectionObserver' in window) {
    const obs = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting) e.target.classList.add('v', 'visible');
      });
    }, { threshold: 0.15 });
    fadeItems.forEach(el => obs.observe(el));
  } else {
    fadeItems.forEach(el => el.classList.add('v', 'visible'));
  }

  const showCopied = target => {
    if (!target) return;
    const original = target.textContent;
    target.textContent = '已复制';
    setTimeout(() => { target.textContent = original; }, 1800);
  };

  const copyText = (text, target) => {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => showCopied(target)).catch(() => {});
    }
  };

  window.copyQQ = () => {
    copyText('1097909459', document.getElementById('qq-display'));
  };

  const qqCard = document.getElementById('qq-card');
  if (qqCard) {
    qqCard.addEventListener('click', () => {
      copyText('1097909459', qqCard.querySelector('#qq-display, .ct-label, span'));
    });
  }
});
