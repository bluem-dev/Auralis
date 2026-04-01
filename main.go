package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/windows"

	"auralis/internal/app"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	a := app.New()

	err := wails.Run(&options.App{
		Title:     "Auralis",
		Width:     960,
		Height:    620,
		MinWidth:  800,
		MinHeight: 540,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 243, G: 243, B: 243, A: 255},
		OnStartup:        a.OnStartup,
		OnShutdown:       a.OnShutdown,
		Bind: []interface{}{
			a,
		},
		Windows: &windows.Options{
			WebviewIsTransparent:              false,
			WindowIsTranslucent:               false,
			DisablePinchZoom:                  true,
			Theme:                             windows.SystemDefault,
			CustomTheme: &windows.ThemeSettings{
				DarkModeTitleBar:   windows.RGB(255, 255, 255),
				DarkModeTitleText:  windows.RGB(26, 26, 26),
				DarkModeBorder:     windows.RGB(220, 220, 220),
				LightModeTitleBar:  windows.RGB(255, 255, 255),
				LightModeTitleText: windows.RGB(26, 26, 26),
				LightModeBorder:    windows.RGB(220, 220, 220),
			},
		},
		// Frameless: ocultamos la barra nativa de Windows.
		// La UI provee su propio titlebar con drag region CSS.
		Frameless:       true,
		CSSDragProperty: "--wails-draggable",
		CSSDragValue:    "drag",
	})
	if err != nil {
		println("Error:", err.Error())
	}
}
