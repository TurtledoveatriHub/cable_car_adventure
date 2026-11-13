module.exports = {
  apps: [
    {
      name: "cablecar-wechat-server",
      script: "./src/server.js",
      cwd: __dirname,
      instances: 1,
      autorestart: true,
      max_memory_restart: "300M",
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
