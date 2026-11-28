#ifndef ABADDON_ARSENAL_HUD_H
#define ABADDON_ARSENAL_HUD_H

// Included once by the HL2 single-player client before memdbgon.h.
#include "c_basehlplayer.h"
#include "hud.h"
#include "hudelement.h"
#include "hud_element_helper.h"
#include "iclientmode.h"
#include <vgui/IScheme.h>
#include <vgui/ISurface.h>
#include <vgui_controls/Panel.h>

class CHudAbaddonArsenal : public CHudElement, public vgui::Panel
{
	DECLARE_CLASS_SIMPLE( CHudAbaddonArsenal, vgui::Panel );

public:
	CHudAbaddonArsenal( const char *elementName )
		: CHudElement( elementName ), BaseClass( g_pClientMode->GetViewport(), "HudAbaddonArsenal" ),
		  m_font( vgui::INVALID_FONT ), m_cellWidth( 0 ), m_lineHeight( 0 )
	{
		SetHiddenBits( HIDEHUD_WEAPONSELECTION | HIDEHUD_PLAYERDEAD | HIDEHUD_INVEHICLE );
		SetPaintBackgroundEnabled( false );
		SetPaintBorderEnabled( false );
		SetMouseInputEnabled( false );
		SetKeyBoardInputEnabled( false );
	}

	virtual bool ShouldDraw()
	{
		return GetFlightPilot() && CHudElement::ShouldDraw() && !engine->IsDrawingLoadingImage();
	}

	virtual void VidInit()
	{
		InvalidateLayout( false, true );
	}

protected:
	virtual void ApplySchemeSettings( vgui::IScheme *scheme )
	{
		BaseClass::ApplySchemeSettings( scheme );
		m_font = scheme->GetFont( "DefaultSmall", true );
		if ( m_font == vgui::INVALID_FONT )
			m_font = scheme->GetFont( "Default" );
		m_textColor = scheme->GetColor( "Label.TextColor", Color( 213, 225, 229, 255 ) );
	}

	virtual void PerformLayout()
	{
		BaseClass::PerformLayout();
		if ( m_font == vgui::INVALID_FONT )
			return;

		int labelWidth, textHeight;
		vgui::surface()->GetTextSize( m_font, L"W PLASMA", labelWidth, textHeight );
		m_cellWidth = labelWidth + Scale( 12 );
		m_lineHeight = MAX( textHeight, vgui::surface()->GetFontTall( m_font ) );
		const int width = 5 * m_cellWidth;
		const int height = 2 * m_lineHeight + Scale( 17 );
		int hudWidth, hudHeight;
		GetHudSize( hudWidth, hudHeight );
		SetBounds( MAX( 0, hudWidth - width - Scale( 12 ) ), Scale( 12 ), width, height );
	}

	virtual void Paint()
	{
		const C_BaseHLPlayer *pilot = GetFlightPilot();
		if ( !pilot || m_font == vgui::INVALID_FONT || m_cellWidth == 0 )
			return;

		const int pad = Scale( 6 );
		const int width = GetWide();
		const int height = GetTall();
		const int plasmaMount = pilot->GetAbaddonPlasmaMount();
		const Color plasmaColor( 105, 221, 237, 255 );
		vgui::ISurface *surface = vgui::surface();
		surface->DrawSetColor( 12, 20, 24, 192 );
		surface->DrawFilledRect( 0, 0, width, height );
		surface->DrawSetTextFont( m_font );

		const wchar_t *const kineticLabels[] = { L"L MG", L"R MG", L"T MG", L"B MG" };
		const wchar_t *const plasmaLabels[] = { L"L PLASMA", L"R PLASMA", L"T PLASMA", L"B PLASMA" };
		for ( int mount = 0; mount < ARRAYSIZE( kineticLabels ); ++mount )
		{
			const bool plasma = mount == plasmaMount;
			DrawText( pad + mount * m_cellWidth, pad, plasma ? plasmaLabels[mount] : kineticLabels[mount],
				plasma ? plasmaColor : m_textColor );
		}

		wchar_t bay[24];
		V_snwprintf( bay, ARRAYSIZE( bay ), pilot->HasAbaddonGravityMine() ? L"5 GRV %d" : L"5 PLS %d", pilot->GetAbaddonMines() );
		DrawText( pad + 4 * m_cellWidth, pad, bay, pilot->GetAbaddonMines() > 0 ? Color(180,215,150,255) : Color(232,154,101,255) );

		const float charge = clamp( pilot->GetAbaddonEnergy(), 0.0f, 100.0f );
		wchar_t energy[24];
		V_snwprintf( energy, ARRAYSIZE( energy ), L"ENERGY %d%%", static_cast<int>( charge + 0.5f ) );
		const int readingsY = pad + m_lineHeight + Scale( 3 );
		DrawText( pad, readingsY, energy, m_textColor );
		if ( plasmaMount >= 0 && plasmaMount < ARRAYSIZE( plasmaLabels ) )
		{
			wchar_t magazine[24];
			V_snwprintf( magazine, ARRAYSIZE( magazine ), L"PLASMA %d/6",
				clamp( pilot->GetAbaddonPlasmaRounds(), 0, 6 ) );
			int labelWidth, labelHeight;
			surface->GetTextSize( m_font, magazine, labelWidth, labelHeight );
			DrawText( width - pad - labelWidth, readingsY, magazine, plasmaColor );
		}

		const int barY = height - Scale( 4 );
		surface->DrawSetColor( 51, 71, 79, 255 );
		surface->DrawFilledRect( pad, barY, width - pad, barY + Scale( 2 ) );
		surface->DrawSetColor( plasmaColor );
		surface->DrawFilledRect( pad, barY, pad + static_cast<int>( ( width - 2 * pad ) * charge / 100 ), barY + Scale( 2 ) );
	}

private:
	static const C_BaseHLPlayer *GetFlightPilot()
	{
		C_BaseHLPlayer *pilot = dynamic_cast<C_BaseHLPlayer *>( C_BasePlayer::GetLocalPlayer() );
		return pilot && pilot->IsAlive() && !pilot->IsObserver() && pilot->IsAbaddonFlightEnabled() ? pilot : NULL;
	}

	int Scale( int value )
	{
		return MAX( 1, vgui::scheme()->GetProportionalScaledValueEx( GetScheme(), value ) );
	}

	static void DrawText( int x, int y, const wchar_t *text, const Color &color )
	{
		vgui::ISurface *surface = vgui::surface();
		surface->DrawSetTextColor( color );
		surface->DrawSetTextPos( x, y );
		surface->DrawPrintText( text, V_wcslen( text ) );
	}

	vgui::HFont m_font;
	Color m_textColor;
	int m_cellWidth;
	int m_lineHeight;
};

DECLARE_HUDELEMENT( CHudAbaddonArsenal );

#endif
