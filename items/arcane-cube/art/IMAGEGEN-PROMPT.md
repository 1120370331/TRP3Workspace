# 六面海潮奥术美术参考

生成方式：内置 imagegen。生成图仅作风格与符号参考；运行时使用手工整数图形重绘的点阵，不采样、嵌入或加载生成 PNG。

参考来源：先前生成的海潮徽记，用于金属、海玻璃和海潮纹样风格。最终六面参考保存在 `references/tidal-six-faces.png`。

最终提示词：

Use case: stylized-concept. Create ONE reference sheet containing EXACTLY SIX distinct flat square face designs for an ocean/tidal arcane puzzle cube. Layout: three equal square panels across, two rows, thin consistent dark gutters. Use the attached image only as an aesthetic reference for teal sea glass, deep navy stone, antique gold trim and ocean magic. Each of the six panels must be a crisp, legible LOW-RESOLUTION PIXEL-ART design, visually about 24 by 24 pixels per face enlarged with hard pixel edges, using a small shared palette, large clean shapes and no noisy detail. The six unique central emblems are: a curling tidal wave; a scallop shell; an arcane trident; a spiral whirlpool; a faceted sea crystal; and a crescent moon over a wave. Each face uses the same thin square gold frame and corner sea-glass studs, while the center is clearly distinguishable. Flat orthographic texture designs only. No cube renders, no perspective, no environment, no labels, no words, no numbers, no watermarks. Six complete panels, all visible. This sheet is only an art reference: the final game will redraw these designs as palette-indexed pixel data embedded in Lua.

重绘源：`../../../tools/build-tidal-pixels.py`（从仓库根目录定位）；输出为24×24、12色的点阵，RLE4压缩数据在 `../src/pixel-art.lua`，预览PNG及可编辑SVG在 `pixels/`。
