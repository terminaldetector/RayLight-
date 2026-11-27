#ifndef ABADDON_RECOVERY_SERVER_H
#define ABADDON_RECOVERY_SERVER_H

#include "abaddon_recovery.h"
#include "Sprite.h"

// Both fields use the pilot's actual flight energy and HL2 health / suit armor.
class CAbaddonRecovery : public CPointEntity
{
    DECLARE_CLASS( CAbaddonRecovery, CPointEntity );
    DECLARE_DATADESC();
public:
    void Spawn();
    void Precache();
    void UpdateOnRemove();
    int ObjectCaps() { return BaseClass::ObjectCaps() & ~FCAP_ACROSS_TRANSITION; }
    static void DropFrom( CHL2_Player *pilot, CBaseEntity *victim );
private:
    void RecoveryThink();
    void CreateLight( CHandle<CSprite> &sprite, float scale, int alpha );
    bool Reachable( CHL2_Player *pilot ) const;
    CHandle<CSprite> m_hHalo, m_hCore;
    bool m_bStation, m_bServicing;
    float m_flExpires, m_flNextPulse;
    float m_flCharge;
    int m_nHull;
};

LINK_ENTITY_TO_CLASS( abaddon_energy_cloud, CAbaddonRecovery );
LINK_ENTITY_TO_CLASS( abaddon_charge_station, CAbaddonRecovery );

BEGIN_DATADESC( CAbaddonRecovery )
    DEFINE_FIELD( m_hHalo, FIELD_EHANDLE ),
    DEFINE_FIELD( m_hCore, FIELD_EHANDLE ),
    DEFINE_FIELD( m_bStation, FIELD_BOOLEAN ),
    DEFINE_FIELD( m_bServicing, FIELD_BOOLEAN ),
    DEFINE_FIELD( m_flExpires, FIELD_TIME ),
    DEFINE_FIELD( m_flNextPulse, FIELD_TIME ),
    DEFINE_FIELD( m_flCharge, FIELD_FLOAT ),
    DEFINE_FIELD( m_nHull, FIELD_INTEGER ),
    DEFINE_THINKFUNC( RecoveryThink ),
END_DATADESC()

void CAbaddonRecovery::Precache()
{
    BaseClass::Precache();
    PrecacheModel( "sprites/glow01.vmt" );
    PrecacheScriptSound( "SuitRecharge.Start" );
}

void CAbaddonRecovery::CreateLight( CHandle<CSprite> &sprite, float scale, int alpha )
{
    sprite = CSprite::SpriteCreate( "sprites/glow01.vmt", GetAbsOrigin(), false );
    if ( sprite )
    {
        sprite->SetTransparency( kRenderTransAdd, m_bStation ? 96 : 144, 222, m_bStation ? 233 : 171, alpha, kRenderFxNone );
        sprite->SetScale( scale );
    }
}

void CAbaddonRecovery::Spawn()
{
    BaseClass::Spawn();
    Precache();
    m_bStation = ClassMatches( "abaddon_charge_station" );
    m_bServicing = false;
    m_flNextPulse = gpGlobals->curtime;
    m_flExpires = gpGlobals->curtime + abaddon::RecoveryCloudLife;
    // Map-authored clouds use the stock mission pickup amounts.
    if ( m_flCharge == 0 && m_nHull == 0 )
    {
        m_flCharge = 22;
        m_nHull = 12;
    }
    CreateLight( m_hHalo, m_bStation ? 1.05f : 1.5f, 54 );
    CreateLight( m_hCore, m_bStation ? .25f : .55f, 119 );
    SetThink( &CAbaddonRecovery::RecoveryThink );
    SetNextThink( gpGlobals->curtime + TICK_INTERVAL );
}

void CAbaddonRecovery::UpdateOnRemove()
{
    if ( m_hHalo ) UTIL_Remove( m_hHalo );
    if ( m_hCore ) UTIL_Remove( m_hCore );
    BaseClass::UpdateOnRemove();
}

bool CAbaddonRecovery::Reachable( CHL2_Player *pilot ) const
{
    if ( !pilot || !pilot->IsAbaddonFlightEnabled() || !pilot->CanAbaddonFly() )
        return false;
    const Vector center = pilot->WorldSpaceCenter();
    if ( center.DistToSqr( GetAbsOrigin() ) > abaddon::RecoveryReach * abaddon::RecoveryReach )
        return false;
    trace_t cover;
    UTIL_TraceLine( GetAbsOrigin(), center, MASK_SOLID_BRUSHONLY, pilot, COLLISION_GROUP_NONE, &cover );
    return !cover.DidHit();
}

void CAbaddonRecovery::RecoveryThink()
{
    const float now = gpGlobals->curtime;
    if ( !m_bStation )
    {
        const float remaining = m_flExpires - now;
        if ( remaining <= 0 )
        {
            UTIL_Remove( this );
            return;
        }
        const float alpha = abaddon::CloudOpacity( remaining );
        const float cycle = sinf( remaining * 3.2f );
        if ( m_hHalo )
        {
            m_hHalo->SetBrightness( int(54 * alpha) );
            m_hHalo->SetScale( 1.5f + .12f * cycle );
        }
        if ( m_hCore )
            m_hCore->SetBrightness( int((110 + 18 * cycle) * alpha) );
    }
    SetNextThink( now + (m_bStation ? .10f : .04f) );
    CHL2_Player *pilot = dynamic_cast<CHL2_Player *>( UTIL_GetLocalPlayer() );
    if ( !Reachable( pilot ) )
    {
        if ( m_bServicing && m_hCore ) m_hCore->SetBrightness( 119, .18f );
        m_bServicing = false;
        return;
    }
    if ( m_bStation && now < m_flNextPulse )
        return;
    const abaddon::RecoveryAmount service = {5, 2, 1};
    const abaddon::RecoveryAmount salvage = {m_flCharge, m_nHull, 9};
    if ( !pilot->ApplyFlightRecovery( m_bStation ? service : salvage ) )
    {
        if ( m_bServicing && m_hCore ) m_hCore->SetBrightness( 119, .18f );
        m_bServicing = false;
        return;
    }
    if ( !m_bServicing ) EmitSound( "SuitRecharge.Start" );
    if ( !m_bStation )
    {
        SetThink( NULL );
        UTIL_Remove( this );
        return;
    }
    m_bServicing = true;
    m_flNextPulse = now + .5f;
    if ( m_hCore ) m_hCore->SetBrightness( 210, .12f );
}

void CAbaddonRecovery::DropFrom( CHL2_Player *pilot, CBaseEntity *victim )
{
    if ( !pilot->IsAbaddonFlightEnabled() || !pilot->IsAlive() || !victim ||
        !(victim->ClassMatches( "npc_manhack" ) || victim->ClassMatches( "npc_cscanner" ) ||
          victim->ClassMatches( "npc_clawscanner" )) )
        return;
    CAI_BaseNPC *npc = victim->MyNPCPointer();
    if ( !npc || npc->IRelationType( pilot ) != D_HT || gEntList.NumberOfEdicts() >= MAX_EDICTS - 64 )
        return;
    int count = 0;
    CBaseEntity *ent = NULL;
    while ( (ent = gEntList.FindEntityByClassname( ent, "abaddon_energy_cloud" )) != NULL )
        if ( !ent->IsMarkedForDeletion() && ++count >= 20 ) return;

    CAbaddonRecovery *cloud = static_cast<CAbaddonRecovery *>( CreateEntityByName( "abaddon_energy_cloud" ) );
    if ( !cloud ) return;
    const abaddon::RecoveryAmount reward = abaddon::DroneSalvage( victim->GetMaxHealth() );
    cloud->m_flCharge = reward.energy;
    cloud->m_nHull = reward.hull;
    cloud->SetAbsOrigin( victim->WorldSpaceCenter() );
    DispatchSpawn( cloud );
}

#endif
