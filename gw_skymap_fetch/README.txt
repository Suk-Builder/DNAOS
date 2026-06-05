=== GW裂缝事件skymap批量下载+RA/DEC提取 ===

1. SSH登录服务器:
   ssh root@43.160.235.191
   密码: !Sorao519520

2. 上传fetch_skymaps.py到服务器

3. 运行:
   cd ~ && python3 fetch_skymaps.py

4. 输出: crack_sky_positions.json (13个事件的RA/DEC)

事件清单:
  GW170817, GW191219_163120, GW190814, GW200210_092254
  GW191113_071753, GW190929_012149, GW200115_042309
  GW190412, GW200208_222617, GW151012
  GW200216_220804, GW170104, GW190828_065509
