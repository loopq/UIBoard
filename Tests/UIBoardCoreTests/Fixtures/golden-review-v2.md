---
format: uiboard-review/2
created: 2026-09-24T18:15:42+08:00
image: runtime.png
size: 2225x2400
figma: https://www.figma.com/design/pw7H7us12aHi2IqHDi0bdm/Neku?node-id=128-22976
refs: [ref-1.png]
frames:
  - frame: A
    offset: 0,0
    size: 1080x2400
    source: adb
    device: Pixel 7 (37091JEHN)
    density: 420
    activity: com.stickermobi.avatarmaker/.ui.task.TaskCenterActivity
    hierarchy: hierarchy-A.xml
  - frame: B
    offset: 1145,0
    size: 1080x2400
---

# UI Review

## #1

- frame: A
- rect: 96,412,888,180
- dp: 36.6,157.0,338.3,68.6
- crop: crops/1.png @ 0,304
- views: com.stickermobi.avatarmaker:id/rewards_tab [TextView 96,400,444,192] · com.stickermobi.avatarmaker:id/bonus_tab [TextView 540,400,444,192] · com.stickermobi.avatarmaker:id/tab_track [FrameLayout 60,350,960,100]

黄色选中态应该比紫色底更高，现在两者一样高。

## #2

- frame: B
- rect: 540,1200,0,0
- crop: crops/2.png @ 432,1092

未选中状态下 Tab 文字颜色太浅。

## #3

- frame: A
- rect: 675,2266,0,0
- dp: 257.1,863.2,0.0,0.0
- crop: crops/3.png @ 567,2158
- views: com.stickermobi.avatarmaker:id/nav_create_icon [ImageView 627,2218,96,96] · com.stickermobi.avatarmaker:id/nav_create [LinearLayout 540,2180,270,220] · com.stickermobi.avatarmaker:id/bottom_nav [LinearLayout 0,2180,1080,220]

这个 icon 比设计稿明显偏大。
