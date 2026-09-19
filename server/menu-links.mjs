// Curated official menu pages, matched by exact place ID, not guessed names.
// Checked 2026-09-19. These are links only: no third-party images are copied.
const ikea = {
  url: 'https://www.ikea.com.tw/zh/store/tao-yuan/ikea-food-and-beverage',
  note: 'IKEA 桃園店官方餐點資訊；品項與價格以現場為準。',
  checkedAt: '2026-09-19',
};
const menus = new Map([
  ['ChIJBZCtvxQfaDQRCbE-csEoZjU', ikea],
  ['ChIJD5KtvxQfaDQR_eYa8OJOZM0', ikea],
  ['ChIJa3U5KQAhaDQRcpS-WSYlLbI', {
    url: 'https://www.mcdonalds.com/tw/zh-tw/full-menu.html',
    note: '麥當勞台灣官方菜單；品項與價格以分店現場為準。',
    checkedAt: '2026-09-19',
  }],
]);

export function verifiedMenu(id, now = Date.now()) {
  const menu = menus.get(id);
  if (!menu) return null;
  // Expire manual verification rather than keep advertising unchecked links.
  const age = now - Date.parse(`${menu.checkedAt}T00:00:00Z`);
  return age >= 0 && age < 90 * 86400000 ? menu : null;
}
