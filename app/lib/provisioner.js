export function buildSiteProvisionPlan({ site_name, domain, root_path, php_version = '8.2' }) {
  const safeName = site_name.replace(/[^a-zA-Z0-9.-]/g, '-');
  const vhost = `server {
    listen 80;
    server_name ${domain};
    root ${root_path};
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
`;

  const phpPool = `[$safeName]
user = www-data
group = www-data
listen = /run/php/php${php_version}-fpm.$safeName.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
chdir = /
`;

  return {
    site_name: safeName,
    domain,
    root_path,
    php_version,
    nginx_vhost: vhost,
    php_pool: phpPool,
    task_name: `provision-${safeName}`,
  };
}
