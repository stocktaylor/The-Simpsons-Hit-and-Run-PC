//=============================================================================
// Copyright (c) 2002 Radical Games Ltd.  All rights reserved.
//=============================================================================


#ifndef BUFFERLOADER_HPP
#define BUFFERLOADER_HPP

#include <al.h>
#include <radfile.hpp>
#include <radlinkedclass.hpp>
#include <radsound_hal.hpp>  
#include <radsoundobject.hpp>

class radSoundBufferLoaderWin;

// Declaration (not definition - that's in bufferloader.cpp) of the explicit
// specialization of radLinkedClass<radSoundBufferLoaderWin>'s static data
// members. Must appear before any use that would otherwise implicitly
// instantiate radLinkedClass<radSoundBufferLoaderWin> first -
// [temp.expl.spec] requires an explicit specialization to be declared
// before the first implicit-instantiating use in every translation unit
// that uses it. GCC tolerates the ordering violation this file had before
// this declaration was added, but Clang correctly rejects it (see
// radnamespace.hpp for the same fix applied to another radLinkedClass<T>).
template<> radSoundBufferLoaderWin * radLinkedClass< radSoundBufferLoaderWin >::s_pLinkedClassHead;
template<> radSoundBufferLoaderWin * radLinkedClass< radSoundBufferLoaderWin >::s_pLinkedClassTail;

//=============================================================================
// Component: radSoundBufferLoaderWin
//=============================================================================

class radSoundBufferLoaderWin
	:
    public IRadSoundHalDataSourceCallback,
    public radLinkedClass< radSoundBufferLoaderWin >,
    public radSoundObject
{
    public:

        IMPLEMENT_REFCOUNTED( "radSoundBufferLoaderWin" )

        radSoundBufferLoaderWin(
            IRefCount * pIRefCount_Owner,
            void * pBuffer,
		    IRadSoundHalDataSource * pIRadSoundHalDataSource,
            IRadSoundHalAudioFormat * pIRadSoundHalAudioFormat,
            unsigned int numberOfFrames,
            IRadSoundHalBufferLoadCallback * pISoundBufferCallback );

        virtual void OnDataSourceFramesLoaded( unsigned int framesActuallyRead );

    static void CancelOperations( IRefCount * pIRefCount_Owner );

    void Cancel( void );

    private:
        
        void Start( void );
        void Finish( void );

        ref< IRadSoundHalBufferLoadCallback >	m_xIRadSoundHalBufferLoadCallback;
        ref< IRadSoundHalDataSource >			m_xIRadSoundHalDataSource;
        ref< IRefCount >                        m_xIRefCount_Owner;

        unsigned int m_NumberOfFrames;
        void * m_pBuffer;
        bool m_Cancelled;
};

#endif // BUFFERLOADER_HPP