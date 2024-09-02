# FreeDi
A project aiming to use Qidis X3 series stock displays with mainline Klipper.

Lets unlock the full potential of your printer together!
<p align="center">
  <img src="https://github.com/user-attachments/assets/745a7b53-ab59-433f-a441-291efb53926c" alt="Bild_thumb">
</p>

This here is about the next step in the evolution: <br/>
**Bringing the stock LCD screen back to life!**

---

The LCD firmware is called **X3seriesLCD** and created for those who want to use Qidi X3 series printers<br/>
with mainline (vanilla) Klipper and **the stock LCD screen**.<br/>
But it is more then "only" a screen firmware.<br/>
<br/>
What began as a straightforward tutorial has blossomed into a complete ecosystem.<br/>
Its goal is to give you the best printer experience you can have and as lightweight and pure as it can be.<br/>

This includes:
* Recent armbian bookwork - the base
* Recent Klipper firmware - the 3d-Printer firmware
* X3SeriesLCD - my screen firmware

This makes it a perfect symbiosis and I call it **"FreeDi"** ;)
<p align="center">
  <img src="https://github.com/user-attachments/assets/12e4dae0-9322-4cac-84e7-235b4980031c" alt="Symbiosis">
</p>

But honestly:<br/>
**It is more then this**.<br/>
Have you ever had a look at the stock printer.cfg and macros?<br/>
Yes! Its a mess. <br/>
Its full of garbage sections, not optimized and the naming is "confusing".<br/>
FreeDi has a clear structure, macros have been optimized and created from scratch.<br/>
And of course: No garbage any more!<br/>

What started as a hobby project for my personal use has grown significantly. <br/>
To meet the community's needs, I've spent hundreds of hours working on features I don't even personally need or use <br/>
to give you the best control interface the stock printers can have.<br/>
**I hope you like it!**<br/>

If you appreciate my work and it has been beneficial to you,  <br/>
I would be grateful if you consider supporting my efforts with a tip:<br/>
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/B0B4V3TJ6)
<br/>
<br/>
## But, why creating this project?

I am incredibly thankful and proud that my [FreeQIDI tutorial](https://github.com/Phil1988/FreeQIDI) has gained so much popularity.  
I've seen forum posts, GitHub repositories, and Reddit threads linking to my project in various languages, such as:

* German
* French
* Portuguese
* Spanish
* Russian

And I am very happy that this gave you so much benefit and you like your printers more since.

But I also noticed while many were interested and wanted to get the benefits of a pure and recent system, my guide had a disadvantage that cannot be dismissed out of hand:
No touch screen functionallty any more.

While I appreciate the effort of [CChen616](https://github.com/CChen616) to provide a system based on a recent [bookworm](https://github.com/whb0514/QIDI_Max3_Bookworm), it still has several drawbacks:
* Limited updates: Modified Klipper and Moonraker files prevent easy updates from mainline sources.
* Unreliable thumbnails: Thumbnails only work if configured correctly in your slicer software (and at least for me it never really worked on the stock printer)
* Z-offset risks: Applying the Z-offset to an additional file has reportedly caused "nozzle into bed" accidents for some users.
* Reduced disk space: The additional included software can decrease available disk space.

So I started this project and its quite versataille.<br/>
If you own a different printer but the same/similar LCD, you can start a feature request in the "issues" section.
<br/>
<br/>

## You cant wait, right?
I dont make it any longer.
Head over to the Wiki for the [Installation Guide](https://github.com/Phil1988/FreeDi/wiki/Installation-guide) to use it.
But I invite you to read the other parts as well!
<br/>
<br/>

## Why Should You Use This?

Qidi's X3 series printers are built with hardware that has great potential, but they run on outdated software.  
**With the right software, these printers can work better, faster, and be more user-friendly for everyone.**  
I believe that what I offer provides you with a better overall experience and ensures you aren't locked out of the latest features from Klipper,  
as well as all the great software that integrates with it (such as Moonraker, Mainsail/Fluidd, Crowsnest, Shaketune, and thousands of plugins).

Here's a list of software that unlocks the full functionality of the printer through my clean and updated Armbian-Klipper system:

* Latest Klipper 0.12.0+ instead of 0.10.0  
* Armbian Bookworm instead of Buster  
* Python 3.12 instead of 2.7  
* And all the possibilities that come with the latest software versions (Fluidd, Moonraker, etc.)  
* More available disk space  

However, even though the tutorial was straightforward, there was one drawback that was a dealbreaker for some:  
No more touchscreen.  
You could get a new mainboard and attach an HDMI touchscreen, or use (Tiger-)VNC to turn a wireless screen into a monitor, but come on:  
The printer already has a screen, and you paid for it... So let's get that thing working again! ;)
<br/>
<br/>

## Disclaimer

Before you start, please understand that this is a hobby project, and using my firmware is at your own risk.  
I have spent many hours testing and flashed the LCD more than 1,000 times to ensure it provides the best possible experience,  
but I can't test every possible scenario. If you encounter any issues, please report them here on GitHub.

Please do not contact Qidi support if you have any problems. By making these modifications, you will void your warranty in this regard.  
If you ever want or need to revert to the stock system after flashing my firmware, don't worry – it's possible.  
You can use a "recovery" image provided by Qidi and flash the official *.tft firmware back to the LCD.
<br /><br /><br /><br /><br /><br /><br /><br />





