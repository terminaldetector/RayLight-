#ifndef ABADDON_PROJECTILE_SERVER_H
#define ABADDON_PROJECTILE_SERVER_H

// Included once by the HL2 server player translation unit.
#include "SpriteTrail.h"
#include "baseanimating.h"
#include "effect_dispatch_data.h"
#include "entitylist.h"
#include "te_effect_dispatch.h"

enum AbaddonBoltKind { ABADDON_BOLT_KINETIC, ABADDON_BOLT_PLASMA };

struct AbaddonBoltSpec
{
	AbaddonBoltKind kind;
	float directDamage;
	float splashDamage;
	float splashRadius;
	float hullRadius;
	float maxTravel;
	float lifetime;
};

static const char *const AbaddonBoltClass = "abaddon_flight_bolt";
static const char *const AbaddonBoltModel = "models/crossbow_bolt.mdl";
static const char *const AbaddonPlasmaModel = "models/effects/combineball.mdl";
static const char *const AbaddonBoltTrail = "sprites/bluelaser1.vmt";
static const char *const AbaddonPlasmaImpactSound = "NPC_CombineBall.Explosion";
static int g_nAbaddonFlightBolts = 0;

static void AbaddonTraceBolt( const Vector &start, const Vector &end, float radius,
	const IHandleEntity *bolt, const IHandleEntity *owner, trace_t *trace )
{
	const Vector bounds( radius, radius, radius );
	CTraceFilterSkipTwoEntities filter( bolt, owner, COLLISION_GROUP_PROJECTILE );
	UTIL_TraceHull( start, end, -bounds, bounds, MASK_SHOT_HULL, &filter, trace );
}

class CAbaddonFlightBolt : public CBaseAnimating
{
	DECLARE_CLASS( CAbaddonFlightBolt, CBaseAnimating );
	DECLARE_DATADESC();

public:
	CAbaddonFlightBolt() : m_iKind( ABADDON_BOLT_KINETIC ), m_flTravelLeft( 0.0f ) { ++g_nAbaddonFlightBolts; }
	~CAbaddonFlightBolt() { --g_nAbaddonFlightBolts; }

	void Precache();
	void Spawn();
	void UpdateOnRemove();
	int ObjectCaps() { return BaseClass::ObjectCaps() & ~FCAP_ACROSS_TRANSITION; }

	void SetFlight( CBasePlayer *owner, const Vector &origin, const Vector &velocity,
		const AbaddonBoltSpec &spec, unsigned int sequence );

private:
	void FlightThink();
	void Impact( trace_t &hit, CBaseEntity *owner );
	void PlasmaSplash( const Vector &origin, CBaseEntity *owner, CBaseEntity *directTarget );

	CHandle< CSpriteTrail > m_hTrail;
	Vector m_vecFlightVelocity;
	float m_flLastStep;
	float m_flDeadline;
	float m_flTravelLeft;
	float m_flHullRadius;
	float m_flDirectDamage;
	float m_flSplashDamage;
	float m_flSplashRadius;
	int m_iKind;
	unsigned int m_nSequence;
};

LINK_ENTITY_TO_CLASS( abaddon_flight_bolt, CAbaddonFlightBolt );

BEGIN_DATADESC( CAbaddonFlightBolt )
	DEFINE_THINKFUNC( FlightThink ),
	DEFINE_FIELD( m_hTrail, FIELD_EHANDLE ),
	DEFINE_FIELD( m_vecFlightVelocity, FIELD_VECTOR ),
	DEFINE_FIELD( m_flLastStep, FIELD_TIME ),
	DEFINE_FIELD( m_flDeadline, FIELD_TIME ),
	DEFINE_FIELD( m_flTravelLeft, FIELD_FLOAT ),
	DEFINE_FIELD( m_flHullRadius, FIELD_FLOAT ),
	DEFINE_FIELD( m_flDirectDamage, FIELD_FLOAT ),
	DEFINE_FIELD( m_flSplashDamage, FIELD_FLOAT ),
	DEFINE_FIELD( m_flSplashRadius, FIELD_FLOAT ),
	DEFINE_FIELD( m_iKind, FIELD_INTEGER ),
	DEFINE_FIELD( m_nSequence, FIELD_INTEGER ),
END_DATADESC()

void CAbaddonFlightBolt::Precache()
{
	BaseClass::Precache();
	PrecacheModel( AbaddonBoltModel );
	PrecacheModel( AbaddonPlasmaModel );
	PrecacheModel( AbaddonBoltTrail );
	PrecacheScriptSound( AbaddonPlasmaImpactSound );
}

void CAbaddonFlightBolt::SetFlight( CBasePlayer *owner, const Vector &origin,
	const Vector &velocity, const AbaddonBoltSpec &spec, unsigned int sequence )
{
	SetOwnerEntity( owner );
	SetAbsOrigin( origin );
	QAngle angles;
	VectorAngles( velocity, angles );
	SetAbsAngles( angles );
	m_vecFlightVelocity = velocity;
	m_flLastStep = gpGlobals->curtime;
	m_flDeadline = m_flLastStep + spec.lifetime;
	m_flTravelLeft = spec.maxTravel;
	m_flHullRadius = spec.hullRadius;
	m_flDirectDamage = spec.directDamage;
	m_flSplashDamage = spec.splashDamage;
	m_flSplashRadius = spec.splashRadius;
	m_iKind = spec.kind;
	m_nSequence = sequence;
}

void CAbaddonFlightBolt::Spawn()
{
	BaseClass::Spawn();
	const bool plasma = m_iKind == ABADDON_BOLT_PLASMA;
	SetModel( plasma ? AbaddonPlasmaModel : AbaddonBoltModel );
	SetSolid( SOLID_NONE );
	SetMoveType( MOVETYPE_NONE );
	AddEffects( EF_NOSHADOW );
	if ( plasma )
		SetModelScale( 0.65f );

	if ( GetOwnerEntity() )
	{
		m_hTrail = CSpriteTrail::SpriteTrailCreate( AbaddonBoltTrail, GetAbsOrigin(), true );
		if ( m_hTrail )
		{
			m_hTrail->FollowEntity( this );
			m_hTrail->SetTransparency( kRenderTransAdd, plasma ? 66 : 174, plasma ? 216 : 215,
				255, 225, kRenderFxNone );
			m_hTrail->SetStartWidth( plasma ? 14.0f : 3.0f );
			m_hTrail->SetEndWidth( plasma ? 2.0f : 0.0f );
			m_hTrail->SetLifeTime( plasma ? 0.17f : 0.065f );
		}
	}
	SetSimulationTime( gpGlobals->curtime );
	SetThink( &CAbaddonFlightBolt::FlightThink );
	SetNextThink( gpGlobals->curtime + TICK_INTERVAL );
}

void CAbaddonFlightBolt::UpdateOnRemove()
{
	if ( m_hTrail )
		UTIL_Remove( m_hTrail );
	BaseClass::UpdateOnRemove();
}

void CAbaddonFlightBolt::FlightThink()
{
	CBaseEntity *owner = GetOwnerEntity();
	if ( !owner || m_flTravelLeft <= 0.0f || !IsInWorld() )
	{
		UTIL_Remove( this );
		return;
	}

	const float now = gpGlobals->curtime;
	const float stepEnd = MIN( now, m_flDeadline );
	const float elapsed = MAX( stepEnd - m_flLastStep, 0.0f );
	m_flLastStep = stepEnd;
	if ( elapsed > 0.0f )
	{
		Vector delta = m_vecFlightVelocity * elapsed;
		const float distance = delta.Length();
		const float travel = MIN( distance, m_flTravelLeft );
		if ( travel < distance )
			delta *= travel / distance;

		const Vector origin = GetAbsOrigin();
		trace_t hit;
		AbaddonTraceBolt( origin, origin + delta, m_flHullRadius, this, owner, &hit );
		if ( hit.DidHit() )
		{
			SetThink( NULL );
			if ( !( hit.surface.flags & SURF_SKY ) && !hit.startsolid && !hit.allsolid )
				Impact( hit, owner );
			UTIL_Remove( this );
			return;
		}

		UTIL_SetOrigin( this, hit.endpos );
		SetSimulationTime( now );
		m_flTravelLeft -= travel;
	}

	if ( now >= m_flDeadline || m_flTravelLeft <= 0.0f )
		UTIL_Remove( this );
	else
		SetNextThink( now + TICK_INTERVAL );
}

void CAbaddonFlightBolt::Impact( trace_t &hit, CBaseEntity *owner )
{
	UTIL_SetOrigin( this, hit.endpos );
	const bool plasma = m_iKind == ABADDON_BOLT_PLASMA;
	const int damageType = ( plasma ? DMG_SHOCK : DMG_BULLET ) | DMG_NEVERGIB;
	if ( !plasma )
		UTIL_ImpactTrace( &hit, damageType );

	ConVarRef traceMount( "abaddon_mount_trace", true );
	if ( traceMount.IsValid() && traceMount.GetBool() )
	{
		Msg( "ABADDON_BOLT impact seq=%u muzzle_kind=%s time=%.3f at=%.2f,%.2f,%.2f world=%d\n",
			m_nSequence, plasma ? "plasma" : "kinetic", gpGlobals->curtime,
			hit.endpos.x, hit.endpos.y, hit.endpos.z, hit.DidHitWorld() );
	}

	if ( hit.m_pEnt && !hit.DidHitWorld() && hit.m_pEnt->m_takedamage != DAMAGE_NO )
	{
		Vector direction = m_vecFlightVelocity;
		VectorNormalize( direction );
		CTakeDamageInfo damage( this, owner, m_flDirectDamage, damageType );
		damage.SetDamageForce( direction * ( plasma ? 4000.0f : 1500.0f ) );
		damage.SetDamagePosition( hit.endpos );
		ClearMultiDamage();
		hit.m_pEnt->DispatchTraceAttack( damage, direction, &hit );
		ApplyMultiDamage();
	}

	if ( plasma )
	{
		CEffectData effect;
		effect.m_vOrigin = hit.endpos;
		DispatchEffect( "cball_explode", effect );
		EmitSound( AbaddonPlasmaImpactSound );
		if ( m_flSplashDamage > 0.0f && m_flSplashRadius > 0.0f )
			PlasmaSplash( hit.endpos + hit.plane.normal, owner, hit.m_pEnt );
	}
}

void CAbaddonFlightBolt::PlasmaSplash( const Vector &origin, CBaseEntity *owner, CBaseEntity *directTarget )
{
	CTraceFilterSkipTwoEntities filter( this, owner, COLLISION_GROUP_NONE );
	CBaseEntity *target;
	for ( CEntitySphereQuery sphere( origin, m_flSplashRadius );
		( target = sphere.GetCurrentEntity() ) != NULL; sphere.NextEntity() )
	{
		if ( target == this || target == owner || target == directTarget ||
			target->IsMarkedForDeletion() || target->m_takedamage == DAMAGE_NO )
		{
			continue;
		}

		const Vector point = target->BodyTarget( origin, false );
		Vector direction = point - origin;
		const float distance = VectorNormalize( direction );
		if ( distance >= m_flSplashRadius )
			continue;
		trace_t cover;
		UTIL_TraceLine( origin, point, MASK_SHOT_HULL, &filter, &cover );
		if ( cover.startsolid || ( cover.DidHit() && cover.m_pEnt != target ) )
			continue;

		const float falloff = 1.0f - distance / m_flSplashRadius;
		CTakeDamageInfo damage( this, owner, m_flSplashDamage * falloff, DMG_SHOCK | DMG_NEVERGIB );
		damage.SetDamageForce( direction * ( 4000.0f * falloff ) );
		damage.SetDamagePosition( origin );
		target->TakeDamage( damage );
	}
}

static bool AbaddonLaunchBolt( CBasePlayer *owner, const Vector &origin, const Vector &velocity,
	const AbaddonBoltSpec &spec, unsigned int sequence )
{
	// A launch allocates one bolt and one trail. Leave edicts free for the map
	// and cap the total even if the pilot is firing all four mounts.
	if ( !owner || !origin.IsValid() || !velocity.IsValid() || velocity.LengthSqr() <= 0.0f ||
		spec.hullRadius <= 0.0f || spec.maxTravel <= 0.0f || spec.lifetime <= 0.0f ||
		g_nAbaddonFlightBolts >= 224 || gEntList.NumberOfEdicts() >= MAX_EDICTS - 64 )
	{
		return false;
	}

	trace_t muzzle;
	AbaddonTraceBolt( origin, origin, spec.hullRadius, owner, owner, &muzzle );
	if ( muzzle.DidHit() )
		return false;

	CAbaddonFlightBolt *bolt = static_cast< CAbaddonFlightBolt * >( CreateEntityByName( AbaddonBoltClass ) );
	if ( !bolt )
		return false;
	bolt->SetFlight( owner, origin, velocity, spec, sequence );
	return DispatchSpawn( bolt ) == 0;
}

#endif
