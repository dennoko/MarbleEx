#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

namespace lilToon
{
    public class MarbleExInspector : lilToonInspector
    {
        // custom_insert.hlsl の LIL_MARBLEEX_MODE_* と順序を一致させること
        private const int ModeMarble   = 0;
        private const int ModeAurora   = 1;
        private const int ModeVoronoi  = 2;
        private const int ModeCaustics = 3;

        // lilCustomShaderProperties.lilblock の Alpha Boost の並び順と一致させること
        private const int AlphaModeOff = 0;

        // Common
        MaterialProperty _CustomMarbleEnable;
        MaterialProperty _CustomMarbleMode;
        MaterialProperty _CustomMarbleUVMode;
        MaterialProperty _CustomMarbleMask;
        MaterialProperty _CustomMarbleMaskChannel;
        MaterialProperty _CustomMarbleMaskInvert;
        MaterialProperty _CustomMarbleScale;
        MaterialProperty _CustomMarbleSpeed;
        MaterialProperty _CustomMarbleDetail;
        MaterialProperty _CustomMarbleBlend;
        MaterialProperty _CustomMarbleEmission;

        // Alpha Boost
        MaterialProperty _CustomMarbleAlphaMode;
        MaterialProperty _CustomMarbleAlphaBoost;
        MaterialProperty _CustomMarbleAlphaContrast;

        // Palette
        MaterialProperty _CustomMarbleColor1;
        MaterialProperty _CustomMarbleColor2;
        MaterialProperty _CustomMarbleColor3;

        // Marble
        MaterialProperty _CustomMarbleWarp;
        MaterialProperty _CustomMarbleVeinFreq;
        MaterialProperty _CustomMarbleContrast;

        // Aurora
        MaterialProperty _CustomAuroraStretch;
        MaterialProperty _CustomAuroraSharpness;

        // Voronoi
        MaterialProperty _CustomVoronoiEdge;
        MaterialProperty _CustomVoronoiBreath;
        MaterialProperty _CustomVoronoiCellVariation;

        // Caustics
        MaterialProperty _CustomCausticsSharpness;
        MaterialProperty _CustomCausticsLayerScale;

        private static bool isShowMarbleExProperties;
        private const string shaderName = "dennokoworks/MarbleEx";

        protected override void LoadCustomProperties(MaterialProperty[] props, Material material)
        {
            isCustomShader = true;
            ReplaceToCustomShaders();
            isShowRenderMode = !material.shader.name.Contains("Optional");

            _CustomMarbleEnable         = FindProperty("_CustomMarbleEnable",         props);
            _CustomMarbleMode           = FindProperty("_CustomMarbleMode",           props);
            _CustomMarbleUVMode         = FindProperty("_CustomMarbleUVMode",         props);
            _CustomMarbleMask           = FindProperty("_CustomMarbleMask",           props);
            _CustomMarbleMaskChannel    = FindProperty("_CustomMarbleMaskChannel",    props);
            _CustomMarbleMaskInvert     = FindProperty("_CustomMarbleMaskInvert",     props);
            _CustomMarbleScale          = FindProperty("_CustomMarbleScale",          props);
            _CustomMarbleSpeed          = FindProperty("_CustomMarbleSpeed",          props);
            _CustomMarbleDetail         = FindProperty("_CustomMarbleDetail",         props);
            _CustomMarbleBlend          = FindProperty("_CustomMarbleBlend",          props);
            _CustomMarbleEmission       = FindProperty("_CustomMarbleEmission",       props);

            _CustomMarbleAlphaMode      = FindProperty("_CustomMarbleAlphaMode",      props);
            _CustomMarbleAlphaBoost     = FindProperty("_CustomMarbleAlphaBoost",     props);
            _CustomMarbleAlphaContrast  = FindProperty("_CustomMarbleAlphaContrast",  props);

            _CustomMarbleColor1         = FindProperty("_CustomMarbleColor1",         props);
            _CustomMarbleColor2         = FindProperty("_CustomMarbleColor2",         props);
            _CustomMarbleColor3         = FindProperty("_CustomMarbleColor3",         props);

            _CustomMarbleWarp           = FindProperty("_CustomMarbleWarp",           props);
            _CustomMarbleVeinFreq       = FindProperty("_CustomMarbleVeinFreq",       props);
            _CustomMarbleContrast       = FindProperty("_CustomMarbleContrast",       props);

            _CustomAuroraStretch        = FindProperty("_CustomAuroraStretch",        props);
            _CustomAuroraSharpness      = FindProperty("_CustomAuroraSharpness",      props);

            _CustomVoronoiEdge          = FindProperty("_CustomVoronoiEdge",          props);
            _CustomVoronoiBreath        = FindProperty("_CustomVoronoiBreath",        props);
            _CustomVoronoiCellVariation = FindProperty("_CustomVoronoiCellVariation", props);

            _CustomCausticsSharpness    = FindProperty("_CustomCausticsSharpness",    props);
            _CustomCausticsLayerScale   = FindProperty("_CustomCausticsLayerScale",   props);
        }

        // [lilEnum] のドロップダウン項目は displayName の '|' 以降から作られる。
        // ラベルを別文字列で上書きすると選択肢が消えるので、必ず displayName を渡す。
        private void DrawEnum(MaterialProperty prop)
        {
            if (prop == null) return;
            m_MaterialEditor.ShaderProperty(prop, prop.displayName);
        }

        // Alpha Boost は LIL_RENDER == 2（アルファブレンド）でしか意味を持たない。
        // Opaque では直前に fd.col.a = 1.0 が入り、Cutout では出力アルファが使われない。
        // 誤警告を避けたいので、判定できない場合は「効く」側に倒している。
        private static bool IsAlphaBlended(Material material)
        {
            if (material == null || material.shader == null) return true;

            string name = material.shader.name;

            // lilToonMulti は 1 本のシェーダーで全モードを賄うため _TransparentMode を見る
            if (name.Contains("Multi"))
            {
                return material.HasProperty("_TransparentMode")
                    && material.GetFloat("_TransparentMode") != 0.0f;
            }

            return name.Contains("Transparent")
                || name.Contains("Overlay")
                || name.Contains("Fur")
                || name.Contains("Gem")
                || name.Contains("Refraction");
        }

        protected override void DrawCustomProperties(Material material)
        {
            isShowMarbleExProperties = Foldout("MarbleEx", "MarbleEx", isShowMarbleExProperties);
            if (!isShowMarbleExProperties) return;

            EditorGUILayout.BeginVertical(boxOuter);
            EditorGUILayout.LabelField("MarbleEx", customToggleFont);
            EditorGUILayout.BeginVertical(boxInnerHalf);

            m_MaterialEditor.ShaderProperty(_CustomMarbleEnable, "Enable");

            // 無効時はパラメーターを触れないようにして、効果が出ない状態での混乱を防ぐ
            using (new EditorGUI.DisabledScope(_CustomMarbleEnable.floatValue < 0.5f))
            {
                // [lilEnum] は「渡されたラベル文字列」を '|' で分割して選択肢を作る。
                // ここでラベルを短く上書きすると選択肢が空の Popup になってしまうため、
                // .lilblock に書いた displayName（"Pattern|Marble|..."）をそのまま渡すこと。
                DrawEnum(_CustomMarbleMode);
                DrawEnum(_CustomMarbleUVMode);

                DrawLine();

                EditorGUILayout.LabelField("Mask", EditorStyles.boldLabel);
                m_MaterialEditor.TexturePropertySingleLine(
                    new GUIContent("Mask", "白 = パターンを適用 / 黒 = ベースカラーのまま"),
                    _CustomMarbleMask);
                m_MaterialEditor.TextureScaleOffsetProperty(_CustomMarbleMask);
                DrawEnum(_CustomMarbleMaskChannel);
                m_MaterialEditor.ShaderProperty(_CustomMarbleMaskInvert, "Invert Mask");

                DrawLine();

                m_MaterialEditor.ShaderProperty(_CustomMarbleScale,  "Scale");
                m_MaterialEditor.ShaderProperty(_CustomMarbleSpeed,  "Speed");
                m_MaterialEditor.ShaderProperty(_CustomMarbleDetail, "Detail (fBm Gain)");
                m_MaterialEditor.ShaderProperty(_CustomMarbleBlend,  "Blend");
                m_MaterialEditor.ShaderProperty(_CustomMarbleEmission, "Emission");

                DrawLine();

                EditorGUILayout.LabelField("Alpha Boost", EditorStyles.boldLabel);
                DrawEnum(_CustomMarbleAlphaMode);

                bool alphaBoostOn = (int)_CustomMarbleAlphaMode.floatValue != AlphaModeOff;
                using (new EditorGUI.DisabledScope(!alphaBoostOn))
                {
                    m_MaterialEditor.ShaderProperty(_CustomMarbleAlphaBoost,
                        new GUIContent("Strength", "1 で該当部分が完全に不透明になる"));
                    m_MaterialEditor.ShaderProperty(_CustomMarbleAlphaContrast,
                        new GUIContent("Contrast", "大きいほど、選んだ成分が強い部分だけに絞られる"));
                }

                if (alphaBoostOn && !IsAlphaBlended(material))
                {
                    EditorGUILayout.HelpBox(
                        "Alpha Boost はアルファブレンドを行う Rendering Mode（Transparent 系）でのみ効果があります。" +
                        "現在のシェーダーは不透明 / Cutout のため出力アルファが使われません。",
                        MessageType.Info);
                }

                DrawLine();

                EditorGUILayout.LabelField("Palette", EditorStyles.boldLabel);
                m_MaterialEditor.ShaderProperty(_CustomMarbleColor1, "Color 1");
                m_MaterialEditor.ShaderProperty(_CustomMarbleColor2, "Color 2");
                m_MaterialEditor.ShaderProperty(_CustomMarbleColor3, "Color 3");

                DrawLine();

                // 選択中のパターンに関係するパラメーターだけを出す
                int mode = (int)_CustomMarbleMode.floatValue;
                switch (mode)
                {
                    case ModeAurora:
                        EditorGUILayout.LabelField("Aurora", EditorStyles.boldLabel);
                        m_MaterialEditor.ShaderProperty(_CustomAuroraStretch,   "Vertical Stretch");
                        m_MaterialEditor.ShaderProperty(_CustomAuroraSharpness, "Sharpness");
                        break;

                    case ModeVoronoi:
                        EditorGUILayout.LabelField("Voronoi", EditorStyles.boldLabel);
                        m_MaterialEditor.ShaderProperty(_CustomVoronoiEdge,          "Edge Width");
                        m_MaterialEditor.ShaderProperty(_CustomVoronoiBreath,        "Breath");
                        m_MaterialEditor.ShaderProperty(_CustomVoronoiCellVariation, "Cell Variation");
                        break;

                    case ModeCaustics:
                        EditorGUILayout.LabelField("Caustics", EditorStyles.boldLabel);
                        m_MaterialEditor.ShaderProperty(_CustomCausticsSharpness,  "Sharpness");
                        m_MaterialEditor.ShaderProperty(_CustomCausticsLayerScale, "2nd Layer Scale");
                        break;

                    case ModeMarble:
                    default:
                        EditorGUILayout.LabelField("Marble", EditorStyles.boldLabel);
                        m_MaterialEditor.ShaderProperty(_CustomMarbleWarp,     "Warp Strength");
                        m_MaterialEditor.ShaderProperty(_CustomMarbleVeinFreq, "Vein Frequency");
                        m_MaterialEditor.ShaderProperty(_CustomMarbleContrast, "Contrast");
                        break;
                }

                if (mode == ModeVoronoi || mode == ModeCaustics)
                {
                    EditorGUILayout.HelpBox(
                        "Voronoi / Caustics は 1 ピクセルあたり 9 セルを走査します。Quest 向けには Scale を小さめにしてください。",
                        MessageType.Info);
                }
            }

            EditorGUILayout.EndVertical();
            EditorGUILayout.EndVertical();
        }

        protected override void ReplaceToCustomShaders()
        {
            lts         = Shader.Find(shaderName + "/lilToon");
            ltsc        = Shader.Find("Hidden/" + shaderName + "/Cutout");
            ltst        = Shader.Find("Hidden/" + shaderName + "/Transparent");
            ltsot       = Shader.Find("Hidden/" + shaderName + "/OnePassTransparent");
            ltstt       = Shader.Find("Hidden/" + shaderName + "/TwoPassTransparent");

            ltso        = Shader.Find("Hidden/" + shaderName + "/OpaqueOutline");
            ltsco       = Shader.Find("Hidden/" + shaderName + "/CutoutOutline");
            ltsto       = Shader.Find("Hidden/" + shaderName + "/TransparentOutline");
            ltsoto      = Shader.Find("Hidden/" + shaderName + "/OnePassTransparentOutline");
            ltstto      = Shader.Find("Hidden/" + shaderName + "/TwoPassTransparentOutline");

            ltstess     = Shader.Find("Hidden/" + shaderName + "/Tessellation/Opaque");
            ltstessc    = Shader.Find("Hidden/" + shaderName + "/Tessellation/Cutout");
            ltstesst    = Shader.Find("Hidden/" + shaderName + "/Tessellation/Transparent");
            ltstessot   = Shader.Find("Hidden/" + shaderName + "/Tessellation/OnePassTransparent");
            ltstesstt   = Shader.Find("Hidden/" + shaderName + "/Tessellation/TwoPassTransparent");

            ltstesso    = Shader.Find("Hidden/" + shaderName + "/Tessellation/OpaqueOutline");
            ltstessco   = Shader.Find("Hidden/" + shaderName + "/Tessellation/CutoutOutline");
            ltstessto   = Shader.Find("Hidden/" + shaderName + "/Tessellation/TransparentOutline");
            ltstessoto  = Shader.Find("Hidden/" + shaderName + "/Tessellation/OnePassTransparentOutline");
            ltstesstto  = Shader.Find("Hidden/" + shaderName + "/Tessellation/TwoPassTransparentOutline");

            ltsref      = Shader.Find("Hidden/" + shaderName + "/Refraction");

            ltsover     = Shader.Find(shaderName + "/[Optional] Overlay");
            ltsoover    = Shader.Find(shaderName + "/[Optional] OverlayOnePass");

            // 以下のバリアントは .lilcontainer を用意していないため、あえて上書きしない。
            // lilShaderManager.InitializeShaders() が入れた素の lilToon シェーダーが
            // そのまま残るので、該当モードに切り替えると MarbleEx を失う代わりに
            // マテリアルが壊れずに素の lilToon へフォールバックする。
            //   Lite         : Quest 向け。Object Space UV 非対応かつ Voronoi/Caustics が実用外
            //   Fur / FurOnly: パターンは乗るが需要が薄くパス数が多い
            //   Gem          : lil_pass_forward_gem.hlsl が BEFORE_SHADOW を呼ばないため効果ゼロ
            //   RefractionBlur / FakeShadow : 同上（refblur / fakeshadow パスに BEFORE_SHADOW が無い）
            //   OutlineOnly  : [Optional] のニッチ用途
            //   Multi        : キーワード分岐でバリアント数が最大になる
        }
    }
}
#endif
