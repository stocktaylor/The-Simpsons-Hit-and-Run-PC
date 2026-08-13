//=============================================================================
// Copyright (C) 2002 Radical Entertainment Ltd.  All rights reserved.
//
// File:        soundrenderercallback.h
//
// Description: Declaration of SoundRenderingPlayerCallback class.  Used from
//              sound renderer for player-related callbacks.
//
// History:     06/07/2002 + Created -- Darren
//
//=============================================================================

#ifndef SOUNDRENDERERCALLBACK_H
#define SOUNDRENDERERCALLBACK_H

//========================================
// Nested Includes
//========================================
#include <radobject.hpp>
#include <radlinkedclass.hpp>

#include <sound/soundrenderer/soundsystem.h>

//========================================
// Forward References
//========================================

struct SimpsonsSoundPlayerCallback;
class SimpsonsSoundPlayer;
class SoundRenderingPlayerCallback;

// Declaration (not definition - that's in soundrenderercallback.cpp) of the
// explicit specialization of radLinkedClass<SoundRenderingPlayerCallback>'s
// static data members. Must appear before any use that would otherwise
// implicitly instantiate radLinkedClass<SoundRenderingPlayerCallback>
// first - [temp.expl.spec] requires an explicit specialization to be
// declared before the first implicit-instantiating use in every
// translation unit that uses it. GCC tolerates the ordering violation this
// file had before this declaration was added, but Clang correctly rejects
// it (see radnamespace.hpp for the same fix applied to another
// radLinkedClass<T>).
template<> SoundRenderingPlayerCallback * radLinkedClass< SoundRenderingPlayerCallback >::s_pLinkedClassHead;
template<> SoundRenderingPlayerCallback * radLinkedClass< SoundRenderingPlayerCallback >::s_pLinkedClassTail;

//=============================================================================
//
// Synopsis:    SoundRenderingPlayerCallback
//
//=============================================================================

class SoundRenderingPlayerCallback : public Sound::IDaSoundPlayerState,
                                     public radLinkedClass< SoundRenderingPlayerCallback >,
                                     public radRefCount
{
    public:
        IMPLEMENT_REFCOUNTED( "SoundRenderingPlayerCallback" );

        SoundRenderingPlayerCallback( SimpsonsSoundPlayer& playerObj,
                                      SimpsonsSoundPlayerCallback* callbackObj );
        virtual ~SoundRenderingPlayerCallback();

        void CancelGameCallbackAndRelease();

        static void CompletionCheck();

        // Currently unused
        void OnSoundReady( void* pData );

        // Called when sound renderer player has completed playback
        void OnSoundDone( void* pData );

    private:
        //Prevent wasteful constructor creation.
        SoundRenderingPlayerCallback();
        SoundRenderingPlayerCallback( const SoundRenderingPlayerCallback& original );
        SoundRenderingPlayerCallback& operator=( const SoundRenderingPlayerCallback& rhs );

        SimpsonsSoundPlayerCallback* m_callbackObj;
        SimpsonsSoundPlayer* m_playerObj;
};


#endif // SOUNDRENDERERCALLBACK_H

