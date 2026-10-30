FROM docker.io/frappe/erpnext:v15.32.0

USER frappe
WORKDIR /home/frappe/frappe-bench

# ================================================================
# 1) 中文本地化 App：ERPNext China Location
#    正确仓库：https://github.com/saoxia/erpnext_china   分支 develop
#    备选镜像：https://gitee.com/webvip/erpnext_china     分支 develop
#
#    注意：digitwise/erpnext_china 不存在（404）。git 遇到 404 会误以为
#    是私有库而索要账号密码，报
#      fatal: could not read Username for 'https://github.com'
#    看起来像网络问题，实际是地址写错。
#
#    为什么必须打进镜像：多容器架构下 backend / websocket / frontend
#    必须共用同一个镜像；且 sites 是挂载目录，每次重建都会覆盖，
#    只有装进镜像（apps/ 与 env/ 在镜像里）才能持久保留。
# ================================================================
RUN (bench get-app --branch develop https://github.com/saoxia/erpnext_china.git \
     || (rm -rf apps/erpnext_china && \
         bench get-app --branch develop https://gitee.com/webvip/erpnext_china.git)) \
    && bench build --app erpnext_china

# ================================================================
# 2) 补齐 erpnext_china 漏声明的 Python 依赖
#    该 App 的 pyproject.toml 只声明了 5 个依赖（pycryptodome / xmltodict /
#    qrcode / paramiko / sqlalchemy），但 button_permission.py 在模块顶层写了
#      import pandas as pd
#      import numpy as np
#    Frappe 安装时同步 DocType 会立即加载控制器，走到 Button Permission 就抛：
#      Module import failed for Button Permission ...
#      Error: No module named 'pandas'
#    安装进度因此停在 44%（不是巧合，就是该文件在列表里的位置）。
#
#    关键：必须装进 env 虚拟环境。用系统 pip install pandas 装完，
#          bench 运行时依然看不到，照样报 No module named 'pandas'。
# ================================================================
RUN /home/frappe/frappe-bench/env/bin/pip install --no-cache-dir \
        "pandas>=2.0,<3" "numpy>=1.23" \
    && /home/frappe/frappe-bench/env/bin/python -c \
       "import pandas, numpy; print('deps ok:', pandas.__version__, numpy.__version__)"
