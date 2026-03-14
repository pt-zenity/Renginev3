module.exports = {
  apps: [
    {
      name: 'rengine-web',
      script: 'python3',
      args: 'manage.py runserver 0.0.0.0:3000',
      cwd: '/home/user/webapp/web',
      env: {
        DJANGO_SETTINGS_MODULE: 'reNgine.settings_local',
        PYTHONUNBUFFERED: '1',
      },
      watch: false,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 5,
    }
  ]
}
