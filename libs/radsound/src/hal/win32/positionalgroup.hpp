//=============================================================================
// Copyright (c) 2002 Radical Games Ltd.  All rights reserved.
//=============================================================================


#ifndef RADSOUNDHALPOSITIONALGROUP_HPP
#define RADSOUNDHALPOSITIONALGROUP_HPP

//============================================================================
// Include Files
//============================================================================

#include <radlinkedclass.hpp>
#include <radsound_hal.hpp>
#include <radsoundobject.hpp>

//============================================================================
// Forward Declarations
//============================================================================

struct radSoundHalPositionalGroup;
struct radSoundhalPositionalEntity;

// Declaration (not definition - that's in positionalgroup.cpp) of the
// explicit specialization of radLinkedClass<radSoundHalPositionalGroup>'s
// static data members. Must appear before any use that would otherwise
// implicitly instantiate radLinkedClass<radSoundHalPositionalGroup> first -
// [temp.expl.spec] requires an explicit specialization to be declared
// before the first implicit-instantiating use in every translation unit
// that uses it. GCC tolerates the ordering violation this file had before
// this declaration was added, but Clang correctly rejects it (see
// radnamespace.hpp for the same fix applied to another radLinkedClass<T>).
template<> radSoundHalPositionalGroup * radLinkedClass< radSoundHalPositionalGroup >::s_pLinkedClassHead;
template<> radSoundHalPositionalGroup * radLinkedClass< radSoundHalPositionalGroup >::s_pLinkedClassTail;

//============================================================================
// radSoundhalPostionalEntity
//============================================================================

struct radSoundHalPositionalEntity
{
	public:

		virtual void OnApplyPositionalInfo( float listenerRolloffFactor ) = 0;

	private: friend struct radSoundHalPositionalGroup;

		radSoundHalPositionalEntity * m_pNext;
		radSoundHalPositionalEntity * m_pPrev;
};

//============================================================================
// radSoundhalPostionalGroup
//============================================================================

struct radSoundHalPositionalGroup
	:
	public IRadSoundHalPositionalGroup,
	public radLinkedClass< radSoundHalPositionalGroup >,
	public radSoundObject
{
	public:

		IMPLEMENT_REFCOUNTED( "radSoundHalPositionalGroup" )
		
		radSoundHalPositionalGroup( void );
		virtual ~radSoundHalPositionalGroup( void );

		void AddPositionalEntity( radSoundHalPositionalEntity * pRadSoundHalPositionalEntity );
		void RemovePositionalEntity( radSoundHalPositionalEntity * pRadSoundHalPositionalEntity );

		void UpdatePositionalSettings( float listenerRolloffFactor );

		// IRadSoundHalPositionalGroup

		virtual void  SetPosition( radSoundVector * pPosition );
		virtual void  GetPosition( radSoundVector * pPosition );
		virtual void  SetVelocity( radSoundVector * pVelocity );
		virtual void  GetVelocity( radSoundVector * pVelocity );
		virtual void  SetOrientation( radSoundVector * pFront, radSoundVector * pTop );
		virtual void  GetOrientation( radSoundVector * pFront, radSoundVector * pTop );
		virtual void  SetMinMaxDistance( float min, float max );
		virtual void  GetMinMaxDistance( float * pMin, float * pMax );
		virtual void  SetConeOutsideVolume( float ov );
		virtual float GetConeOutsideVolume( void );
		virtual void  SetConeAngles( float in, float out );
		virtual void  GetConeAngles( float * pIn, float * pOut );

        virtual void  SetOcclusion( float occl ) { rDebugPrintf( "Win32 Occlusion not supported\n" ); }
        virtual float GetOcclusion( void ) { rDebugPrintf( "Win32 Occlusion not supported\n"); return 0.0f; }
        virtual void  SetObstruction( float obst ) { rDebugPrintf( "Win32 Obstruction not supported\n" ); }
        virtual float GetObstruction( void ) { rDebugPrintf( "Win32 Obstruction not supported\n" ); return 0.0f; }

		radSoundVector m_Position;
		radSoundVector m_Velocity;
		radSoundVector m_Direction;
		float m_ConeInnerAngle;
		float m_ConeOuterAngle;
		float m_ConeOuterGain;
		float m_ReferenceDistance;
		float m_MaxDistance;

		radSoundHalPositionalEntity * m_pRadSoundHalPositionalEntity_Head;
};

#endif // RADSOUNDHALPOSITIONALGROUP_HPP


