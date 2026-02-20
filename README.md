

云编译798x特定机型的istoreos风格固件 （p3terx 2024新版 基于ubuntu22.04）

路由器型号：

     JCG Q30 / uax3000e / clx s20l / clx s20p

说明：
     
     24.10闭源WIFI固件（基于immortalwrt）

     默认地址：192.168.30.1  密码：无，直接回车。

H大源码网址: https://github.com/hanwckf/immortalwrt-mt798x

237大佬源码网址: https://github.com/padavanonly/immortalwrt-mt798x-24.10

dailook大佬源码网址: https://github.com/dailook/immortalwrt-mt798x-24.10

21.02分支的脚本参考和借鉴加菲猫大佬的云编译脚本：https://github.com/lgs2007m/Actions-OpenWrt

因为quickstart的首页温度无法显示正常温度读数，原因为/cgi-bin/luci/istore/system/status/ 这个请求没有 cpuTemperature 这个返回值，这个请求是 /usr/lib/lua/luci/controller/istore_backend.lua 在处理的，但 lua 里只是转给了 quickstart 监听的端口，所以核心问题是 istoreos 的 quickstart 不支持这个架构的 CPU 温度获取所以没有输出。使用了地址为：https://gist.github.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa 提供的修复文件：istore_backend.lua。感谢作者的分享。

使用p3terx云编译模板

固件位置：https://github.com/yhlh9982/MT798X-IstoreOS.style/releases
     
注意事项：

     不死u-boot用 H 大的刷，地址：https://github.com/hanwckf/bl-mt798x/releases

     u-boot 刷机方法：https://cmi.hanwckf.top/p/mt798x-uboot-usage

     更新刷写固件时，跨版本更新的，记得不要保存设置，每次更新系统后再按住 rest键8 秒复位一次

     刷写完新固件后，尤其是跨版本更新的，记得先清理浏览器缓存，再访问路由器进行设置。




# Actions-OpenWrt

[![LICENSE](https://img.shields.io/github/license/mashape/apistatus.svg?style=flat-square&label=LICENSE)](https://github.com/P3TERX/Actions-OpenWrt/blob/master/LICENSE)
![GitHub Stars](https://img.shields.io/github/stars/P3TERX/Actions-OpenWrt.svg?style=flat-square&label=Stars&logo=github)
![GitHub Forks](https://img.shields.io/github/forks/P3TERX/Actions-OpenWrt.svg?style=flat-square&label=Forks&logo=github)

A template for building OpenWrt with GitHub Actions

## Usage

- Click the [Use this template](https://github.com/P3TERX/Actions-OpenWrt/generate) button to create a new repository.
- Generate `.config` files using [Lean's OpenWrt](https://github.com/coolsnowwolf/lede) source code. ( You can change it through environment variables in the workflow file. )
- Push `.config` file to the GitHub repository.
- Select `Build OpenWrt` on the Actions page.
- Click the `Run workflow` button.
- When the build is complete, click the `Artifacts` button in the upper right corner of the Actions page to download the binaries.

## Tips

- It may take a long time to create a `.config` file and build the OpenWrt firmware. Thus, before create repository to build your own firmware, you may check out if others have already built it which meet your needs by simply [search `Actions-Openwrt` in GitHub](https://github.com/search?q=Actions-openwrt).
- Add some meta info of your built firmware (such as firmware architecture and installed packages) to your repository introduction, this will save others' time.

## Credits

- [Microsoft Azure](https://azure.microsoft.com)
- [GitHub Actions](https://github.com/features/actions)
- [OpenWrt](https://github.com/openwrt/openwrt)
- [Lean's OpenWrt](https://github.com/coolsnowwolf/lede)
- [tmate](https://github.com/tmate-io/tmate)
- [mxschmitt/action-tmate](https://github.com/mxschmitt/action-tmate)
- [csexton/debugger-action](https://github.com/csexton/debugger-action)
- [Cowtransfer](https://cowtransfer.com)
- [WeTransfer](https://wetransfer.com/)
- [Mikubill/transfer](https://github.com/Mikubill/transfer)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)
- [ActionsRML/delete-workflow-runs](https://github.com/ActionsRML/delete-workflow-runs)
- [dev-drprasad/delete-older-releases](https://github.com/dev-drprasad/delete-older-releases)
- [peter-evans/repository-dispatch](https://github.com/peter-evans/repository-dispatch)

## License

[MIT](https://github.com/P3TERX/Actions-OpenWrt/blob/main/LICENSE) © [**P3TERX**](https://p3terx.com)
