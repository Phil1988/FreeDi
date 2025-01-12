# FreeDi
A project aiming to use QIDIs X3 series printers with the stock display with latest klipper and OTA update support.<br/>
**Lets unlock the full potential of your printer together!**
<p align="center">
  <img src="https://github.com/user-attachments/assets/745a7b53-ab59-433f-a441-291efb53926c" alt="unlock">
</p>

Current supported printers:
* **X-Max 3**
* **X-Plus 3**
* **X-Smart 3**
<br>

Future support:
* * **Q1 Pro** (Estimated firmware release: April 2025)
  
<br>

Possibly working:
* * **Plus 4** (klipper/python experts needed, please get in touch with me if interessted)




<br/>
If you appreciate my work and it has been beneficial to you,  <br/>
I would be grateful if you consider supporting my efforts with a ko-fi:<br/>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/B0B4V3TJ6)

This also helps me to justify puting more time to maintain this project for the future :)

---
## Why Should You Use This?

Qidi's X3 series printers are built with hardware that has great potential, but they run on outdated software.  
**With the right software, these printers can work better, faster, and be more user-friendly for everyone.**  
I believe that what I offer provides you with a better overall experience.<br>
It ensures you aren't locked out of the latest features from Klipper, as well as all the great software that integrates with it <br/>
(such as Moonraker, Mainsail/Fluidd, Crowsnest, Shaketune, and thousands of plugins).

Here's a list of improvements that unlocks the full functionality of the printer through my clean and updated Armbian-Klipper system:

* **OTA Updates** instead of updating with an USB thumb drive (takes ~4min for a full update instead of ~40min)
* **Pure Klipper** instead of a modified/hacked klipper and moonraker (not upgradable)
* **Latest Klipper 0.12.0+** instead of 0.10.0
* **Armbian Bookworm** instead of Buster  
* **Python 3.12** instead of 2.7
* And all the possibilities that come with the latest software versions (Fluidd, Moonraker, etc.)  
* More available disk space 
<br/>

**But it is more than this.** <br/>
Have you ever taken a look at the stock printer config and macros?<br/>
Yes! It's a mess.<br/>
It's full of unnecessary sections, not optimized, and the naming is confusing.<br/>

**FreeDi has a clear structure**<br/>
Everything has a clear naming.
Macros have been optimized.
And of course: No garbage any more!<br/>
You will notice many things are now snappier and just works better/faster eg. adaptive bed meshing is now almost twice as fast.<br/>

It also fixes the "System starts abnormally"-error
<p align="center">
  <img src="https://github.com/user-attachments/assets/a98c5b18-c3e9-48b0-a21b-7799c58e283e" alt="animated_menue"><img src="https://github.com/Phil1988/FreeDi/blob/master/animation.gif" alt="animated_menue">
</p>

What started as a hobby project for my personal use has grown significantly. <br/>
To meet the community's needs, I've spent hundreds of hours working on features I don't<br/>
even personally need or use to give you the best control interface the stock printers can have.<br/>
**I hope you like it!**<br/>

---
## The Touchscreen Ecosystem
The LCD software is called **FreeDiLCD** and created for those who want to use Qidi X3 series printers<br/>
with mainline (vanilla) Klipper and **the stock LCD screen**.<br/>
<p align="center">
  <img src="https://github.com/user-attachments/assets/378c20ba-1330-44b9-b7c2-e433fe61a699" alt="menue_teaser">
</p>

If you want to see more, check out the [menue guide](https://github.com/Phil1988/FreeDi/wiki/Menue-guide) for a walk through the most important functions.<br/>
<br/>

## But, why creating this project?

I am incredibly thankful and proud that my [FreeQIDI tutorial](https://github.com/Phil1988/FreeQIDI) has gained so much popularity.<br/>
And I am very happy that this gave you so much benefit and you like your printers more since.<br/>

But I also noticed while many were interested and wanted to get the benefits of a pure and recent system, my guide had a disadvantage that cannot be dismissed out of hand:<br/>
No touch screen functionallty any more.<br/>
You could get a new mainboard and attach an HDMI touchscreen, or use (Tiger-)VNC to turn a wireless screen into a monitor, but come on:  <br/>
The printer already has a screen, and you paid for it... So let's get that thing working again! ;)<br/>

Additionally my FreeQIDI tutorial was mainly followed by the more "techy people" and simple users have been somehow locked out.<br/>
My goal is to give **every owner** of a X-3 series printer an improved user experience over the stock system.<br/>

While I appreciate the effort of [CChen616](https://github.com/CChen616) to provide a system based on a recent [bookworm](https://github.com/whb0514/QIDI_Max3_Bookworm), it still has several drawbacks:
* Limited updates: Modified Klipper and Moonraker files prevent easy updates from mainline sources.
* Unreliable thumbnails: Thumbnails only work if configured correctly in your slicer software (and at least for me it never really worked on the stock printer)
* Z-offset risks: Applying the Z-offset to an additional file has reportedly caused "nozzle into bed" accidents for some users.
* Reduced disk space: The additional included software can decrease available disk space.
* And is still not optimized at all. Sorry!

So I started this project and its quite versataille.<br/>
If you own a different printer with the same/similar LCD, you can start a feature request in the "issues" section.<br>
Thats how X-Smart 3 support was done :)
<br/>
<br/>
## You cant wait, right?
I dont make it any longer.<br/>
Head over to the [Wiki](https://github.com/Phil1988/FreeDi/wiki) for the [Installation Guide](https://github.com/Phil1988/FreeDi/wiki/Installation-guide) to use it.<br/>
But I invite you to read the other parts as well!
<br/>
<br/>

## Disclaimer

Before you start, please understand that this is a hobby project and using my firmware is at your own risk.  
I have spent many hours testing and flashed the LCD more than 1,000 times to ensure it provides <br/>
the best possible experience, but I can't test every possible scenario. If you encounter any issues,<br/>
please report them here on GitHub.

Please do not contact Qidi support if you have any problems. By making these modifications,<br/> 
you will void your warranty in this regard.<br/>  
If you ever want or need to revert to the stock system after flashing my firmware, don't worry – it's possible.<br/>  
You can use a "recovery" image provided by Qidi and flash the official *.tft firmware back to the LCD.
<br/>
<br/>
## Notice Regarding Guides, Contributions And Sharing

I kindly ask that you **do not copy or redistribute any parts of my guide and software** without explicit permission.<br/>
In the past, sections of my work have been used without proper credit and claimed as their work.<br/>
Incorrect parts have been added to other guides and resulted in additional effort on my part.<br/>
This resulted in me being contacted for support related to these guides which had errors.<br/>
I hope you do understand that I dont like to spend extra time to fix other faults :).<br/>
<br/>
**However, feel free to share the guide with others as long as proper credit is given!**<br/>
The more users can benefit from it, the happier I get ;)<br/>
<br/>
I invite everyone to share and collaborate to make this the "go-to" place for X3-Series improvements.
If you have suggestions or improvements, I warmly invite you to **submit your contributions directly to me**.<br/>
I will gladly consider integrating them to improve the guide and firmwares for everyone.<br/>
This not only improves the usability for everyone, but also helps to ensure accuracy and reduces unnecessary support issues.<br/>
<br/>
Thank you for respecting this request and for helping to foster a supportive and fair community.<br/>
<br/><br/>





