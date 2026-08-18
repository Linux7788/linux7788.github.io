const menuButton = document.querySelector('.menu-toggle');
const nav = document.querySelector('.main-nav');

menuButton.addEventListener('click', () => {
  const isOpen = menuButton.getAttribute('aria-expanded') === 'true';
  menuButton.setAttribute('aria-expanded', String(!isOpen));
  nav.classList.toggle('open', !isOpen);
});

document.querySelectorAll('.main-nav a').forEach(link => link.addEventListener('click', () => {
  menuButton.setAttribute('aria-expanded', 'false');
  nav.classList.remove('open');
}));

document.querySelectorAll('.service-trigger').forEach(trigger => {
  trigger.addEventListener('click', () => {
    const card = trigger.closest('.service-card');
    const wasOpen = card.classList.contains('open');
    document.querySelectorAll('.service-card.open').forEach(openCard => {
      openCard.classList.remove('open');
      openCard.querySelector('.service-trigger').setAttribute('aria-expanded', 'false');
    });
    if (!wasOpen) {
      card.classList.add('open');
      trigger.setAttribute('aria-expanded', 'true');
    }
  });
});

const devices = document.querySelectorAll('.device-object');
const deviceName = document.querySelector('.device-name');
const deviceNames = ['SMARTPHONE / READY', 'APPLE WATCH / READY', 'LAPTOP / READY', 'MACBOOK / READY'];
let activeDevice = 0;
if (devices.length && deviceName) setInterval(() => {
  devices[activeDevice].classList.remove('active');
  activeDevice = (activeDevice + 1) % devices.length;
  devices[activeDevice].classList.add('active');
  deviceName.textContent = deviceNames[activeDevice];
}, 3200);

const observer = new IntersectionObserver(entries => entries.forEach(entry => {
  if (entry.isIntersecting) { entry.target.classList.add('is-visible'); observer.unobserve(entry.target); }
}), { threshold: 0.12 });
document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
document.getElementById('year').textContent = new Date().getFullYear();
