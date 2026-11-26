#ifndef ABADDON_MINE_SERVER_H
#define ABADDON_MINE_SERVER_H

#include "Sprite.h"
#include "ai_basenpc.h"
#include "abaddon_mine_bay.h"

static const char *const AbaddonMineClass = "abaddon_flight_mine";
static const char *const AbaddonMineGlow = "sprites/glow01.vmt";

class CAbaddonMine : public CBaseAnimating
{
    DECLARE_CLASS( CAbaddonMine, CBaseAnimating );
    DECLARE_DATADESC();

public:
    void Precache();
    void Spawn();
    void UpdateOnRemove();
    int ObjectCaps() { return BaseClass::ObjectCaps() & ~FCAP_ACROSS_TRANSITION; }
    static bool Deploy( CHL2_Player *pilot, const Vector &position, abaddon::MineType kind );

private:
    abaddon::MineType Kind() const { return static_cast<abaddon::MineType>( m_iKind ); }
    void MineThink();
    void Detonate( CBaseEntity *trigger );
    bool CanReach( CBaseEntity *target, float radius, Vector &toward, float &falloff );
    bool Hostile( CBaseEntity *target ) const;
    void UpdateLight();

    int m_iKind;
    bool m_bArmed;
    float m_flBorn, m_flArmAt, m_flExpireAt;
    CHandle<CSprite> m_hBeacon;
};

LINK_ENTITY_TO_CLASS( abaddon_flight_mine, CAbaddonMine );
BEGIN_DATADESC( CAbaddonMine )
    DEFINE_FIELD( m_iKind, FIELD_INTEGER ),
    DEFINE_FIELD( m_bArmed, FIELD_BOOLEAN ),
    DEFINE_FIELD( m_flBorn, FIELD_TIME ),
    DEFINE_FIELD( m_flArmAt, FIELD_TIME ),
    DEFINE_FIELD( m_flExpireAt, FIELD_TIME ),
    DEFINE_FIELD( m_hBeacon, FIELD_EHANDLE ),
    DEFINE_THINKFUNC( MineThink ),
END_DATADESC()

void CAbaddonMine::Precache()
{
    BaseClass::Precache();
    PrecacheModel( "models/drmd/mine_plasma.mdl" );
    PrecacheModel( "models/drmd/mine_gravity.mdl" );
    PrecacheModel( AbaddonMineGlow );
    PrecacheScriptSound( "NPC_RollerMine.Tossed" );
    PrecacheScriptSound( "NPC_CombineBall.Explosion" );
}

void CAbaddonMine::UpdateLight()
{
    if ( !m_hBeacon )
        return;
    const bool well = Kind() == abaddon::GravityMine;
    m_hBeacon->SetTransparency( kRenderTransAdd, well ? 176 : 94, well ? 132 : 216, 244,
        m_bArmed ? 214 : 72, kRenderFxNone );
    m_hBeacon->SetScale( m_bArmed ? 0.29f : 0.12f, 0.18f );
}

void CAbaddonMine::Spawn()
{
    BaseClass::Spawn();
    Precache();
    const bool well = Kind() == abaddon::GravityMine;
    SetModel( well ? "models/drmd/mine_gravity.mdl" : "models/drmd/mine_plasma.mdl" );
    SetSolid( SOLID_NONE );
    SetMoveType( MOVETYPE_NONE );
    const abaddon::MineProfile &spec = abaddon::MineStats( Kind() );
    m_flBorn = gpGlobals->curtime;
    m_flArmAt = m_flBorn + spec.armDelay;
    m_flExpireAt = m_flBorn + spec.life;
    m_bArmed = well;
    Vector up;
    GetVectors( NULL, NULL, &up );
    m_hBeacon = CSprite::SpriteCreate( AbaddonMineGlow, GetAbsOrigin() + up * 8, false );
    UpdateLight();
    SetThink( &CAbaddonMine::MineThink );
    SetNextThink( m_flBorn + .1f );
}

void CAbaddonMine::UpdateOnRemove()
{
    if ( m_hBeacon )
        UTIL_Remove( m_hBeacon );
    BaseClass::UpdateOnRemove();
}

bool CAbaddonMine::Hostile( CBaseEntity *target ) const
{
    CAI_BaseNPC *npc = target->MyNPCPointer();
    return npc && npc->IsAlive() && npc->IRelationType( GetOwnerEntity() ) == D_HT;
}

bool CAbaddonMine::CanReach( CBaseEntity *target, float radius, Vector &toward, float &falloff )
{
    const Vector from = GetAbsOrigin();
    const Vector point = target->BodyTarget( from, false );
    toward = from - point;
    falloff = abaddon::MineFalloff( VectorNormalize( toward ), radius );
    if ( falloff <= 0 )
        return false;
    trace_t cover;
    CTraceFilterSkipTwoEntities filter( this, GetOwnerEntity(), COLLISION_GROUP_NONE );
    UTIL_TraceLine( from, point, MASK_SHOT_HULL, &filter, &cover );
    return !cover.startsolid && ( !cover.DidHit() || cover.m_pEnt == target );
}

void CAbaddonMine::MineThink()
{
    if ( !GetOwnerEntity() || !GetOwnerEntity()->IsAlive() )
    {
        UTIL_Remove( this );
        return;
    }
    const abaddon::MinePhase phase = abaddon::PhaseAt( gpGlobals->curtime, m_flArmAt, m_flExpireAt );
    if ( phase == abaddon::MineExpired )
    {
        Detonate( NULL );
        return;
    }
    SetNextThink( gpGlobals->curtime + .1f );
    if ( phase == abaddon::MineArming )
        return;
    if ( !m_bArmed )
    {
        m_bArmed = true;
        UpdateLight();
        EmitSound( "NPC_RollerMine.Tossed" );
    }

    const bool well = Kind() == abaddon::GravityMine;
    const float radius = abaddon::MineStats( Kind() ).senseRadius;
    CBaseEntity *target;
    for ( CEntitySphereQuery sphere( GetAbsOrigin(), radius ); (target = sphere.GetCurrentEntity()) != NULL; sphere.NextEntity() )
    {
        const bool hostile = Hostile( target );
        IPhysicsObject *physics = target->VPhysicsGetObject();
        const bool movable = well && physics && physics->IsMoveable() && target->ClassMatches( "prop_physics*" );
        Vector toward;
        float falloff;
        if ( (!hostile && !movable) || target->IsMarkedForDeletion() || !CanReach( target, radius, toward, falloff ) )
            continue;
        if ( !well )
        {
            Detonate( target );
            return;
        }
        const Vector impulse = toward * (30.0f * falloff);
        if ( physics && physics->IsMoveable() )
            physics->AddVelocity( &impulse, NULL );
        else if ( hostile )
            target->ApplyAbsVelocityImpulse( impulse );
        if ( hostile )
            target->TakeDamage( CTakeDamageInfo( this, GetOwnerEntity(), 1.5f, DMG_SHOCK ) );
    }
}

void CAbaddonMine::Detonate( CBaseEntity *trigger )
{
    SetThink( NULL );
    const abaddon::MineProfile &spec = abaddon::MineStats( Kind() );
    CBaseEntity *target;
    for ( CEntitySphereQuery sphere( GetAbsOrigin(), spec.blastRadius ); (target = sphere.GetCurrentEntity()) != NULL; sphere.NextEntity() )
    {
        if ( target->IsMarkedForDeletion() || target->m_takedamage == DAMAGE_NO ||
            !( Hostile( target ) || FClassnameIs( target, "func_breakable" ) || target->ClassMatches( "prop_physics*" ) ) )
            continue;
        Vector toward;
        float falloff;
        if ( !CanReach( target, spec.blastRadius, toward, falloff ) )
            continue;
        CTakeDamageInfo damage( this, GetOwnerEntity(), target == trigger ? 120.0f : spec.damage * falloff, DMG_SHOCK );
        damage.SetDamagePosition( GetAbsOrigin() );
        damage.SetDamageForce( toward * (-5000.0f * falloff) );
        target->TakeDamage( damage );
    }
    CEffectData fx;
    fx.m_vOrigin = GetAbsOrigin();
    DispatchEffect( "cball_explode", fx );
    EmitSound( "NPC_CombineBall.Explosion" );
    UTIL_Remove( this );
}

bool CAbaddonMine::Deploy( CHL2_Player *pilot, const Vector &position, abaddon::MineType kind )
{
    if ( gEntList.NumberOfEdicts() >= MAX_EDICTS - 64 )
        return false;
    CAbaddonMine *mine = static_cast<CAbaddonMine *>( CreateEntityByName( AbaddonMineClass ) );
    if ( !mine )
        return false;
    mine->m_iKind = kind;
    mine->SetOwnerEntity( pilot );
    mine->SetAbsOrigin( position );
    mine->SetAbsAngles( pilot->EyeAngles() );
    if ( DispatchSpawn( mine ) != 0 )
        return false;

    CAbaddonMine *oldest = NULL;
    CBaseEntity *ent = NULL;
    int count = 0;
    while ( (ent = gEntList.FindEntityByClassname( ent, AbaddonMineClass )) != NULL )
    {
        CAbaddonMine *other = static_cast<CAbaddonMine *>( ent );
        if ( other == mine || other->IsMarkedForDeletion() || other->GetOwnerEntity() != pilot || other->Kind() != kind )
            continue;
        ++count;
        if ( !oldest || other->m_flBorn < oldest->m_flBorn )
            oldest = other;
    }
    if ( oldest && count >= abaddon::MineStats( kind ).activeLimit )
        UTIL_Remove( oldest );
    return true;
}

class CAbaddonMineSupply : public CBaseAnimating
{
    DECLARE_CLASS( CAbaddonMineSupply, CBaseAnimating );
    DECLARE_DATADESC();
public:
    void Precache() { BaseClass::Precache(); PrecacheModel( "models/drmd/supply.mdl" ); }
    void Spawn()
    {
        BaseClass::Spawn();
        Precache();
        SetModel( "models/drmd/supply.mdl" );
        SetMoveType( MOVETYPE_NONE );
        SetSolid( SOLID_BBOX );
        SetSolidFlags( FSOLID_TRIGGER | FSOLID_NOT_SOLID );
        UTIL_SetSize( this, Vector(-18,-18,-14), Vector(18,18,14) );
        SetTouch( &CAbaddonMineSupply::Collect );
    }
private:
    void Collect( CBaseEntity *other )
    {
        CHL2_Player *pilot = dynamic_cast<CHL2_Player *>( other );
        if ( !pilot || !pilot->IsAlive() || !pilot->IsAbaddonFlightEnabled() || !pilot->RefillAbaddonMines() )
            return;
        SetTouch( NULL );
        UTIL_Remove( this );
    }
};
LINK_ENTITY_TO_CLASS( abaddon_mine_supply, CAbaddonMineSupply );
BEGIN_DATADESC( CAbaddonMineSupply )
    DEFINE_ENTITYFUNC( Collect ),
END_DATADESC()

#endif
