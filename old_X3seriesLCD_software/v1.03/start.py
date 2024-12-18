import main 
import printer
import lcd

def main():
    from main import X3seriesLCD
    x = X3seriesLCD()
    x.startLCD()

if __name__ == "__main__":
    main()