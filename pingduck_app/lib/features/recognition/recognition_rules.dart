/// Data for [Recognizer] (recognition.dart): brand aliases, product families
/// and Apple model identifiers. Patterns are matched case-insensitively.
/// Add entries from real devices; every rule should name a signal a device
/// actually sends.
library;

/// A brand and what its OUI registry names or self-reported maker strings
/// look like ("LCFC(Hefei) Electronics" builds Lenovo PCs).
typedef BrandRule = ({String name, String pattern});

const brandRules = <BrandRule>[
  (name: 'Apple', pattern: r'^apple\b'),
  (name: 'Google', pattern: r'^google\b|^nest labs'),
  (name: 'Amazon', pattern: r'^amazon\b'),
  (name: 'Samsung', pattern: r'^samsung\b'),
  (name: 'Lenovo', pattern: r'^lenovo\b|^lcfc\b|^motorola mobility'),
  (name: 'HP', pattern: r'^hp\b|^hewlett'),
  (name: 'Dell', pattern: r'^dell\b'),
  (name: 'Microsoft', pattern: r'^microsoft\b'),
  (name: 'Gigabyte', pattern: r'^giga-?byte\b'),
  (name: 'ASUS', pattern: r'^asustek\b|^asus\b'),
  (name: 'MSI', pattern: r'^micro-star\b'),
  (name: 'ASRock', pattern: r'^asrock\b'),
  (name: 'Intel', pattern: r'^intel\b'),
  (name: 'TP-Link', pattern: r'^tp-?link\b'),
  (name: 'Netgear', pattern: r'^netgear\b'),
  (name: 'Ubiquiti', pattern: r'^ubiquiti\b'),
  (name: 'Synology', pattern: r'^synology\b'),
  (name: 'QNAP', pattern: r'^qnap\b'),
  (name: 'Raspberry Pi', pattern: r'^raspberry pi\b'),
  (name: 'Sonos', pattern: r'^sonos\b'),
  (name: 'Roku', pattern: r'^roku\b'),
  (name: 'Sony', pattern: r'^sony\b'),
  (name: 'LG', pattern: r'^lg electronics\b|^lg innotek\b'),
  (name: 'Philips Hue', pattern: r'^signify\b|^philips lighting\b'),
  (name: 'GE Lighting', pattern: r'^ge lighting\b'),
  (name: 'Hikvision', pattern: r'^hangzhou hikvision\b'),
  (name: 'Brother', pattern: r'^brother\b'),
  (name: 'Canon', pattern: r'^canon\b'),
  (name: 'Epson', pattern: r'^seiko epson\b|^epson\b'),
  (name: 'Xiaomi', pattern: r'^xiaomi\b|^beijing xiaomi\b'),
  (name: 'OnePlus', pattern: r'^oneplus\b'),
  (name: 'Nintendo', pattern: r'^nintendo\b'),
  (name: 'Proxmox', pattern: r'^proxmox\b'),
];

/// Makers of Wi-Fi modules and contract manufacturers: the OUI names the
/// part inside, not the product, so they are shown as the network module.
const moduleMakers = <BrandRule>[
  (name: 'Espressif', pattern: r'^espressif\b'),
  (name: 'Tuya', pattern: r'^tuya\b'),
  (name: 'Foxconn (Hon Hai)', pattern: r'^hon hai\b|^foxconn\b'),
  (name: 'Murata', pattern: r'^murata\b'),
  (name: 'AzureWave', pattern: r'^azurewave\b'),
  (name: 'Realtek', pattern: r'^realtek\b'),
  (name: 'MediaTek', pattern: r'^mediatek\b'),
  (name: 'Universal Global Scientific', pattern: r'^universal global scientific\b'),
  (name: 'Liteon', pattern: r'^lite-?on\b'),
  (name: 'Shenzhen', pattern: r'^shenzhen\b'),
];

/// A product family by brand, from the start of the model name.
typedef FamilyRule = ({String brand, String pattern, String family});

const familyRules = <FamilyRule>[
  (brand: 'Lenovo', pattern: r'^thinkcentre\b', family: 'ThinkCentre'),
  (brand: 'Lenovo', pattern: r'^thinkpad\b', family: 'ThinkPad'),
  (brand: 'Lenovo', pattern: r'^ideapad\b', family: 'IdeaPad'),
  (brand: 'Lenovo', pattern: r'^legion\b', family: 'Legion'),
  (brand: 'HP', pattern: r'^officejet pro\b', family: 'OfficeJet Pro'),
  (brand: 'HP', pattern: r'^officejet\b', family: 'OfficeJet'),
  (brand: 'HP', pattern: r'^laserjet\b', family: 'LaserJet'),
  (brand: 'HP', pattern: r'^deskjet\b', family: 'DeskJet'),
  (brand: 'HP', pattern: r'^envy\b', family: 'ENVY'),
  (brand: 'Google', pattern: r'^chromecast\b', family: 'Chromecast'),
  (brand: 'Google', pattern: r'^(google )?nest\b', family: 'Nest'),
  (brand: 'Google', pattern: r'^pixel\b', family: 'Pixel'),
  (brand: 'Apple', pattern: r'^iphone\b', family: 'iPhone'),
  (brand: 'Apple', pattern: r'^ipad\b', family: 'iPad'),
  (brand: 'Apple', pattern: r'^macbook\b', family: 'MacBook'),
  (brand: 'Apple', pattern: r'^imac\b', family: 'iMac'),
  (brand: 'Apple', pattern: r'^mac (mini|studio|pro)\b', family: 'Mac'),
  (brand: 'Apple', pattern: r'^apple tv\b', family: 'Apple TV'),
  (brand: 'Apple', pattern: r'^homepod\b', family: 'HomePod'),
  (brand: 'Amazon', pattern: r'^echo\b', family: 'Echo'),
  (brand: 'Amazon', pattern: r'^fire tv\b', family: 'Fire TV'),
  (brand: 'Samsung', pattern: r'^galaxy\b', family: 'Galaxy'),
  (brand: 'Samsung', pattern: r'^[a-z]?[uq]\d{4}', family: 'Smart TV'),
  (brand: 'TP-Link', pattern: r'^archer\b', family: 'Archer'),
  (brand: 'TP-Link', pattern: r'^deco\b', family: 'Deco'),
  (brand: 'Synology', pattern: r'^ds\d', family: 'DiskStation'),
  (brand: 'Roku', pattern: r'^roku\b', family: 'Roku'),
  (brand: 'Sonos', pattern: r'^(sonos )?(one|beam|arc|era|move|roam|five)\b', family: 'Sonos speakers'),
];

/// Apple model identifiers (mDNS `model=`/`am=`) and the product they name.
const appleModels = <String, String>{
  'MacBookPro': 'MacBook Pro',
  'MacBookAir': 'MacBook Air',
  'MacBook': 'MacBook',
  'Macmini': 'Mac mini',
  'MacPro': 'Mac Pro',
  'Mac': 'Mac',
  'iMac': 'iMac',
  'iPhone': 'iPhone',
  'iPad': 'iPad',
  'AppleTV': 'Apple TV',
  'AudioAccessory': 'HomePod',
};

/// Hostname words that name a kind of device, never a person. A device's
/// fingerprint keeps these and blanks every other word (fingerprint.dart).
const hostWords = <String>{
  'iphone', 'ipad', 'macbook', 'imac', 'mac', 'mini', 'air', 'pro', 'appletv', 'homepod', 'watch',
  'android', 'galaxy', 'pixel', 'oneplus', 'xiaomi', 'redmi',
  'desktop', 'laptop', 'pc', 'workstation', 'server', 'nas', 'diskstation', 'ds',
  'printer', 'hp', 'epson', 'brother', 'canon', 'officejet', 'laserjet', 'deskjet', 'envy', 'npi',
  'chromecast', 'nest', 'google', 'home', 'echo', 'amazon', 'kindle', 'fire', 'firetv', 'roku', 'sonos',
  'tv', 'samsung', 'lg', 'webos', 'tizen', 'bravia', 'sony', 'xbox', 'playstation', 'ps4', 'ps5', 'switch',
  'esp', 'esp32', 'esp8266', 'tasmota', 'shelly', 'wled', 'tuya', 'wiz', 'hue', 'kasa', 'tapo', 'ring',
  'camera', 'cam', 'doorbell', 'thermostat', 'plug', 'bulb', 'light', 'speaker',
  'raspberrypi', 'pi', 'proxmox', 'pve', 'ubuntu', 'debian', 'unraid', 'truenas', 'synology', 'qnap',
  'router', 'ap', 'unifi', 'udm', 'archer', 'deco', 'orbi', 'eero', 'gateway',
  'thinkpad', 'thinkcentre', 'ideapad', 'legion', 'dell', 'optiplex', 'latitude', 'xps', 'surface',
};
