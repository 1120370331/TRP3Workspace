// Local, declarative packages. Resolution never downloads or executes package code.
const own = (o,k) => Object.hasOwn(o,k);
function check(ok,message) { if (!ok) throw new Error(message); }
const id = value => typeof value === 'string' && /^[a-z][a-z0-9-]*$/.test(value);
const record = value => value && typeof value === 'object' && !Array.isArray(value);

export function resolvePackages(catalog, requested) {
  check(record(catalog) && catalog.schemaVersion === 1 && typeof catalog.version === 'string', 'Invalid engine package catalog');
  check(record(catalog.packages) && own(catalog.packages,'runtime'), 'Package catalog requires runtime');
  const order = catalog.moduleOrder;
  check(Array.isArray(order) && order.length > 0 && order.every(id) && new Set(order).size === order.length, 'Invalid package module order');
  const owners = new Map();
  for (const [name,pkg] of Object.entries(catalog.packages)) {
    check(id(name) && record(pkg) && Array.isArray(pkg.dependencies) && Array.isArray(pkg.modules), `Invalid package: ${name}`);
    check(pkg.dependencies.every(id) && new Set(pkg.dependencies).size === pkg.dependencies.length, `Invalid dependencies: ${name}`);
    check(pkg.modules.length > 0, `Empty package: ${name}`);
    for (const mod of pkg.modules) {
      check(order.includes(mod) && !owners.has(mod), `Unknown or multiply owned module: ${mod}`);
      owners.set(mod,name);
    }
  }
  check(order.every(mod=>owners.has(mod)), 'Unowned engine module');
  const visit = (name, selected, visiting, path) => {
    check(own(catalog.packages,name), `Unknown engine package: ${name}`);
    check(!visiting.has(name), `Package dependency cycle: ${[...path,name].join(' -> ')}`);
    if (selected.has(name)) return;
    visiting.add(name);
    for (const dependency of [...catalog.packages[name].dependencies].sort()) visit(dependency,selected,visiting,[...path,name]);
    visiting.delete(name);selected.add(name);
  };
  // Validate the whole catalog so an unused broken package cannot hide indefinitely.
  const validated = new Set();
  for (const name of Object.keys(catalog.packages).sort()) visit(name,validated,new Set(),[]);
  const explicit = requested !== undefined;
  requested = explicit ? requested : Object.keys(catalog.packages);
  check(Array.isArray(requested) && requested.every(id) && new Set(requested).size === requested.length, 'packages must be an array of unique package names');
  const selected = new Set();
  for (const name of ['runtime',...requested].sort()) visit(name,selected,new Set(),[]);
  const resolved = [...selected].sort();
  return { version:catalog.version, explicit, requested:[...requested].sort(), resolved,
    automatic:resolved.filter(name=>!requested.includes(name)),
    modules:order.filter(mod=>selected.has(owners.get(mod))),
    dependencies:Object.fromEntries(resolved.map(name=>[name,[...catalog.packages[name].dependencies].sort()])) };
}

export function validatePackageContent(content, plan) {
  const has = name => plan.resolved.includes(name);
  const need = (condition,name,field) => check(!condition || has(name), `content.${field} requires engine package "${name}"`);
  const nonempty = value => value && Object.keys(value).length > 0;
  for (const field of ['prefabs','actions','levels']) need(nonempty(content[field]),'world',field);
  for (const field of ['sounds','music','feedback']) need(nonempty(content[field]),'audio',field);
  need(nonempty(content.effects),'effects','effects');
  need(nonempty(content.particles3d),'particles3d','particles3d');
  need(content.surfaceModelScene === true,'surface-models','surfaceModelScene');
  need(nonempty(content.assets?.models),'surface','assets.models');
}

export function buildSettings(manifest, options = {}) {
  const settings = manifest.build ?? {};
  check(record(settings), 'build must be an object');
  for (const key of Object.keys(settings)) check(['profile','budgets','logs'].includes(key), `Unknown build option: ${key}`);
  const profile = options.profile ?? settings.profile ?? 'development';
  check(['development','release'].includes(profile), 'build.profile must be development or release');
  const budgets = settings.budgets ?? {};
  check(record(budgets), 'build.budgets must be an object');
  for (const [key,value] of Object.entries(budgets)) check(['sourceBytes','exportCharacters'].includes(key) && Number.isSafeInteger(value) && value > 0, `Invalid build budget: ${key}`);
  const logs = {persist:profile==='release'?'manual':'auto', maxBytes:profile==='release'?32768:190000, ...settings.logs};
  check(settings.logs === undefined || record(settings.logs), 'build.logs must be an object');
  check(Object.keys(logs).every(k=>['persist','maxBytes'].includes(k)) && ['auto','manual'].includes(logs.persist) && Number.isInteger(logs.maxBytes) && logs.maxBytes >= 4096 && logs.maxBytes <= 190000, 'Invalid build.logs (persist: auto/manual, maxBytes: 4096..190000)');
  return {profile,budgets,logs};
}

export function checkBudgets(sizes, budgets) {
  for (const [key,limit] of Object.entries(budgets)) check(sizes[key] <= limit, `Build budget exceeded: ${key} ${sizes[key]} > ${limit}`);
}
